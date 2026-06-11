import SwiftUI
import AppKit

@main
struct CloudNotesApp: App {
    @StateObject private var store = NotesStore()
    @StateObject private var cloud = CloudSyncManager()

    init() {
        // Lets the app present a proper foreground window even when
        // launched via `swift run` (no app bundle).
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    var body: some Scene {
        WindowGroup("Notes") {
            ContentView()
                .environmentObject(store)
                .environmentObject(cloud)
                .frame(minWidth: 900, minHeight: 560)
                .task {
                    store.cloud = cloud
                    await cloud.bootstrap() // restores a previous sign-in
                }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Note") { store.createNote() }
                    .keyboardShortcut("n", modifiers: [.command])
                Button("Insert Timestamp") {
                    if let id = store.selectedNoteID { store.appendTimestamp(to: id) }
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            }
            CommandMenu("Format") {
                Button("Bold") { FormatActions.toggleBold() }
                    .keyboardShortcut("b", modifiers: [.command])
                Button("Italic") { FormatActions.toggleItalic() }
                    .keyboardShortcut("i", modifiers: [.command])
                Button("Underline") { FormatActions.toggleUnderline() }
                    .keyboardShortcut("u", modifiers: [.command])
                Divider()
                Button("Highlight") { FormatActions.toggleHighlight() }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                Button("Strikethrough") { FormatActions.toggleStrikethrough() }
                    .keyboardShortcut("x", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(store)
                .environmentObject(cloud)
        }
    }
}
