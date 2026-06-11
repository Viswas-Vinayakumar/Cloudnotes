import SwiftUI

/// The right pane: centered grey date line on top, then a plain text editor.
/// Everything autosaves; the AI button in the toolbar rewrites the note.
struct EditorView: View {
    @EnvironmentObject private var store: NotesStore
    @Binding var aiRunning: Bool

    var body: some View {
        if let note = store.selectedNote {
            VStack(spacing: 0) {
                Text(Self.headerDate(note.updatedAt))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)
                    .padding(.bottom, 4)

                TextEditor(text: binding(for: note))
                    .font(.system(size: 14))
                    .lineSpacing(3)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 16)
                    .disabled(aiRunning)
                    .overlay {
                        if aiRunning {
                            VStack(spacing: 10) {
                                ProgressView()
                                Text("Tidying up your note…")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.background.opacity(0.7))
                        }
                    }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onAppear {
                store.insertTimestampIfStale(for: note.id)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 36))
                    .foregroundStyle(.tertiary)
                Text("Select a note or press ⌘N")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    private func binding(for note: Note) -> Binding<String> {
        Binding(
            get: { store.selectedNote?.content ?? note.content },
            set: { store.updateContent(of: note.id, to: $0) }
        )
    }

    static func headerDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "d MMMM yyyy, h:mm a"
        return f.string(from: date)
    }
}
