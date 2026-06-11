import SwiftUI
import AppKit

/// AppKit-backed rich text editor. Stores formatting as RTF alongside the
/// plain-text mirror used for titles, search, sync merging, and AI cleanup.
struct RichTextEditor: NSViewRepresentable {
    let noteID: UUID
    let rtfBase64: String?
    let plainText: String
    /// Called on every edit with (plainText, rtfData).
    let onEdit: (String, Data) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onEdit: onEdit) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let tv = scroll.documentView as! NSTextView
        tv.isRichText = true
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.font = .systemFont(ofSize: 14)
        tv.textContainerInset = NSSize(width: 16, height: 8)
        tv.drawsBackground = true
        tv.backgroundColor = .textBackgroundColor
        tv.delegate = context.coordinator
        context.coordinator.textView = tv
        load(into: tv, coordinator: context.coordinator)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        // Reload only when the note switched, or its text changed outside the
        // editor (AI cleanup, cloud sync) — never while the user is typing.
        if context.coordinator.currentNoteID != noteID ||
            (tv.string != plainText && context.coordinator.lastEmittedPlain != plainText) {
            load(into: tv, coordinator: context.coordinator)
        }
    }

    private func load(into tv: NSTextView, coordinator: Coordinator) {
        coordinator.suppressCallbacks = true
        defer { coordinator.suppressCallbacks = false }

        let attributed: NSAttributedString
        if let b64 = rtfBase64, let data = Data(base64Encoded: b64),
           let rtf = NSAttributedString(rtf: data, documentAttributes: nil) {
            attributed = rtf
        } else {
            attributed = NSAttributedString(string: plainText, attributes: [
                .font: NSFont.systemFont(ofSize: 14),
                .foregroundColor: NSColor.textColor
            ])
        }
        tv.textStorage?.setAttributedString(attributed)
        coordinator.currentNoteID = noteID
        coordinator.lastEmittedPlain = plainText
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        weak var textView: NSTextView?
        var currentNoteID: UUID?
        var lastEmittedPlain: String = ""
        var suppressCallbacks = false
        private let onEdit: (String, Data) -> Void

        init(onEdit: @escaping (String, Data) -> Void) { self.onEdit = onEdit }

        func textDidChange(_ notification: Notification) {
            guard !suppressCallbacks, let tv = textView, let storage = tv.textStorage else { return }
            let plain = tv.string
            let range = NSRange(location: 0, length: storage.length)
            guard let rtf = storage.rtf(from: range, documentAttributes: [:]) else { return }
            lastEmittedPlain = plain
            onEdit(plain, rtf)
        }
    }
}

/// Formatting actions targeting whichever rich text editor has focus.
/// Bound to the Format menu: ⌘B, ⌘I, ⌘U, ⇧⌘H, ⇧⌘X.
@MainActor
enum FormatActions {
    static let highlightColor = NSColor.systemYellow.withAlphaComponent(0.45)

    private static var textView: NSTextView? {
        NSApp.keyWindow?.firstResponder as? NSTextView
    }

    static func toggleBold() { toggleTrait(.boldFontMask) }
    static func toggleItalic() { toggleTrait(.italicFontMask) }

    static func toggleUnderline() {
        textView?.underline(nil) // native toggle, handles caret + selection
    }

    static func toggleHighlight() {
        toggleAttribute(.backgroundColor, onValue: highlightColor) { current in
            current != nil
        }
    }

    static func toggleStrikethrough() {
        toggleAttribute(.strikethroughStyle,
                        onValue: NSNumber(value: NSUnderlineStyle.single.rawValue)) { current in
            ((current as? NSNumber)?.intValue ?? 0) != 0
        }
    }

    // MARK: - Shared toggling machinery

    private static func toggleTrait(_ trait: NSFontTraitMask) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let fm = NSFontManager.shared
        let range = tv.selectedRange()

        func flipped(_ font: NSFont, on: Bool) -> NSFont {
            on ? fm.convert(font, toHaveTrait: trait)
               : fm.convert(font, toNotHaveTrait: trait)
        }

        if range.length == 0 {
            var attrs = tv.typingAttributes
            let font = (attrs[.font] as? NSFont) ?? .systemFont(ofSize: 14)
            attrs[.font] = flipped(font, on: !fm.traits(of: font).contains(trait))
            tv.typingAttributes = attrs
            return
        }

        var turnOn = true
        if let first = storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont {
            turnOn = !fm.traits(of: first).contains(trait)
        }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range) { value, sub, _ in
            let font = (value as? NSFont) ?? .systemFont(ofSize: 14)
            storage.addAttribute(.font, value: flipped(font, on: turnOn), range: sub)
        }
        storage.endEditing()
        tv.didChangeText()
    }

    private static func toggleAttribute(_ key: NSAttributedString.Key,
                                        onValue: Any,
                                        isOn: (Any?) -> Bool) {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let range = tv.selectedRange()

        if range.length == 0 {
            var attrs = tv.typingAttributes
            if isOn(attrs[key]) { attrs.removeValue(forKey: key) }
            else { attrs[key] = onValue }
            tv.typingAttributes = attrs
            return
        }

        let currentlyOn = isOn(storage.attribute(key, at: range.location, effectiveRange: nil))
        storage.beginEditing()
        if currentlyOn {
            storage.removeAttribute(key, range: range)
        } else {
            storage.addAttribute(key, value: onValue, range: range)
        }
        storage.endEditing()
        tv.didChangeText()
    }
}
