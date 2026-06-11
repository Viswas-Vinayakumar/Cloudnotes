import Foundation

/// A single note. Stored on disk as `<id>.json` inside the sync folder,
/// so iCloud Drive (or any synced folder) keeps every Mac up to date.
struct Note: Identifiable, Codable, Equatable {
    let id: UUID
    var content: String
    var createdAt: Date
    var updatedAt: Date
    /// Snapshot of the content before the last AI cleanup, so it can be reverted.
    var preAIContent: String?

    init(id: UUID = UUID(),
         content: String = "",
         createdAt: Date = .now,
         updatedAt: Date = .now,
         preAIContent: String? = nil) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.preAIContent = preAIContent
    }

    /// First non-empty line, shown as the title in the list (like Notes).
    var title: String {
        let line = content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces)
        return (line?.isEmpty == false ? line! : "New Note")
    }

    /// Second meaningful line, shown as the grey preview in the list.
    var preview: String {
        let lines = content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .dropFirst()
        guard let second = lines.first else { return "No additional text" }
        return String(second).trimmingCharacters(in: .whitespaces)
    }

    var isEmpty: Bool {
        content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
