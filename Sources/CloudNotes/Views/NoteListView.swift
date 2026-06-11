import SwiftUI

/// The middle column: list of notes with title, relative date, and preview.
struct NoteListView: View {
    @EnvironmentObject private var store: NotesStore

    var body: some View {
        List(selection: $store.selectedNoteID) {
            Section(header: Text("Notes").font(.headline)) {
                ForEach(store.filteredNotes) { note in
                    NoteRow(note: note)
                        .tag(note.id)
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                store.deleteNote(note.id)
                            }
                        }
                }
            }
        }
        .listStyle(.inset)
        .overlay {
            if store.filteredNotes.isEmpty {
                ContentUnavailableCompat(
                    text: store.searchText.isEmpty ? "No Notes" : "No Results"
                )
            }
        }
    }
}

private struct NoteRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(note.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(Self.listDate(note.updatedAt))
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(0.8))
                Text(note.preview)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    /// Date formatting like the Notes list: time today, "Yesterday",
    /// weekday within a week, otherwise a short date.
    static func listDate(_ date: Date) -> String {
        let cal = Calendar.current
        let f = DateFormatter()
        if cal.isDateInToday(date) {
            f.dateFormat = "h:mm a"
        } else if cal.isDateInYesterday(date) {
            return "Yesterday"
        } else if let week = cal.date(byAdding: .day, value: -7, to: .now), date > week {
            f.dateFormat = "EEEE"
        } else {
            f.dateFormat = "dd/MM/yy"
        }
        return f.string(from: date)
    }
}

/// Small fallback for "no content" states that also works on macOS 13.
private struct ContentUnavailableCompat: View {
    let text: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "note.text")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
