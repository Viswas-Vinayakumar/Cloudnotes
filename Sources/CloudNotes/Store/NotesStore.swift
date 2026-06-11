import Foundation
import Combine

/// Owns all notes. Persists each note as a JSON file in the sync folder,
/// autosaves with a short debounce (no save button anywhere), and watches
/// the folder so changes synced in from another Mac appear live.
@MainActor
final class NotesStore: ObservableObject {
    @Published private(set) var notes: [Note] = []
    @Published var selectedNoteID: UUID?
    @Published var searchText: String = ""

    /// Where notes live: iCloud Drive, Google Drive (desktop app), or local.
    let syncFolder: URL
    let isUsingiCloud: Bool
    let locationLabel: String

    /// Optional account-based real-time sync (Supabase). When attached,
    /// every local save is pushed and remote changes are merged in live.
    weak var cloud: CloudSyncManager? {
        didSet { wireCloudHandlers() }
    }

    private var saveTasks: [UUID: Task<Void, Never>] = [:]
    private var folderMonitor: DispatchSourceFileSystemObject?
    private var monitorFD: Int32 = -1
    /// Timestamp of the last local write, used to ignore our own file events.
    private var lastLocalWrite: Date = .distantPast

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    enum StorageLocation: String, CaseIterable {
        case auto, icloud, googleDrive, local
    }

    static func iCloudDriveRoot() -> URL? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Google Drive for desktop mounts under ~/Library/CloudStorage/GoogleDrive-<email>.
    static func googleDriveRoot() -> URL? {
        let cs = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/CloudStorage", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: cs, includingPropertiesForKeys: nil) else { return nil }
        guard let gd = entries.first(where: { $0.lastPathComponent.hasPrefix("GoogleDrive") }) else { return nil }
        let myDrive = gd.appendingPathComponent("My Drive", isDirectory: true)
        return FileManager.default.fileExists(atPath: myDrive.path) ? myDrive : gd
    }

    static func folder(for location: StorageLocation) -> (URL, String) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let local = (home.appendingPathComponent("Documents/CloudNotes", isDirectory: true), "Local folder")
        switch location {
        case .icloud:
            if let root = iCloudDriveRoot() {
                return (root.appendingPathComponent("CloudNotes", isDirectory: true), "iCloud Drive")
            }
            return local
        case .googleDrive:
            if let root = googleDriveRoot() {
                return (root.appendingPathComponent("CloudNotes", isDirectory: true), "Google Drive")
            }
            return local
        case .local:
            return local
        case .auto:
            if let root = iCloudDriveRoot() {
                return (root.appendingPathComponent("CloudNotes", isDirectory: true), "iCloud Drive")
            }
            return local
        }
    }

    init() {
        let fm = FileManager.default
        let pref = StorageLocation(rawValue:
            UserDefaults.standard.string(forKey: "storageLocation") ?? "auto") ?? .auto
        let (folder, label) = Self.folder(for: pref)
        syncFolder = folder
        locationLabel = label
        isUsingiCloud = (label == "iCloud Drive")
        try? fm.createDirectory(at: syncFolder, withIntermediateDirectories: true)

        loadAll()
        startMonitoringFolder()

        if notes.isEmpty {
            createNote()
        } else {
            selectedNoteID = sortedNotes.first?.id
        }
    }

    deinit {
        folderMonitor?.cancel()
        if monitorFD >= 0 { close(monitorFD) }
    }

    // MARK: - Derived collections

    var sortedNotes: [Note] {
        notes.sorted { $0.updatedAt > $1.updatedAt }
    }

    var filteredNotes: [Note] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return sortedNotes }
        return sortedNotes.filter {
            $0.content.localizedCaseInsensitiveContains(q)
        }
    }

    var selectedNote: Note? {
        notes.first { $0.id == selectedNoteID }
    }

    // MARK: - CRUD

    @discardableResult
    func createNote() -> Note {
        let stamp = Self.timestampLine(for: .now)
        let note = Note(content: "\n\(stamp)\n")
        notes.append(note)
        selectedNoteID = note.id
        save(note)
        return note
    }

    func updateContent(of id: UUID, to newContent: String) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        guard notes[idx].content != newContent else { return }
        notes[idx].content = newContent
        notes[idx].rtfBase64 = nil
        notes[idx].updatedAt = .now
        scheduleAutosave(notes[idx])
    }

    /// Rich edit from the editor: plain mirror + RTF formatting together.
    func updateRich(of id: UUID, plain: String, rtf: Data) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        let b64 = rtf.base64EncodedString()
        guard notes[idx].content != plain || notes[idx].rtfBase64 != b64 else { return }
        notes[idx].content = plain
        notes[idx].rtfBase64 = b64
        notes[idx].updatedAt = .now
        scheduleAutosave(notes[idx])
    }

    /// Copies all note files into the folder for a new location.
    /// The switch itself takes effect on next launch.
    func migrateStorage(to location: StorageLocation) {
        let (target, _) = Self.folder(for: location)
        let fm = FileManager.default
        try? fm.createDirectory(at: target, withIntermediateDirectories: true)
        guard target != syncFolder else { return }
        for note in notes {
            if let data = try? encoder.encode(note) {
                try? data.write(to: target.appendingPathComponent("\(note.id.uuidString).json"),
                                options: .atomic)
            }
        }
    }

    func applyAIResult(_ cleaned: String, to id: UUID) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[idx].preAIContent = notes[idx].content
        notes[idx].content = cleaned
        notes[idx].rtfBase64 = nil // AI output is plain; formatting resets
        notes[idx].updatedAt = .now
        save(notes[idx])
    }

    func revertAIResult(for id: UUID) {
        guard let idx = notes.firstIndex(where: { $0.id == id }),
              let previous = notes[idx].preAIContent else { return }
        notes[idx].content = previous
        notes[idx].preAIContent = nil
        notes[idx].rtfBase64 = nil
        notes[idx].updatedAt = .now
        save(notes[idx])
    }

    func deleteNote(_ id: UUID) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        let note = notes.remove(at: idx)
        saveTasks[id]?.cancel()
        lastLocalWrite = .now
        try? FileManager.default.removeItem(at: fileURL(for: note.id))
        cloud?.pushDelete(note.id)
        if selectedNoteID == id {
            selectedNoteID = sortedNotes.first?.id
        }
    }

    /// Appends a WhatsApp-style timestamp line and returns the new content.
    func appendTimestamp(to id: UUID) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        var content = notes[idx].content
        if !content.hasSuffix("\n") { content += "\n" }
        content += "\n\(Self.timestampLine(for: .now))\n"
        updateContent(of: id, to: content)
    }

    /// If the note hasn't been touched in a while, drop in a fresh timestamp
    /// automatically before the user's next words — like a new message bubble.
    func insertTimestampIfStale(for id: UUID, gapMinutes: Double = 10) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        if Date.now.timeIntervalSince(notes[idx].updatedAt) > gapMinutes * 60 {
            appendTimestamp(to: id)
        }
    }

    static func timestampLine(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "d MMMM yyyy, h:mm a"
        return "[\(f.string(from: date))]"
    }

    // MARK: - Persistence

    private func fileURL(for id: UUID) -> URL {
        syncFolder.appendingPathComponent("\(id.uuidString).json")
    }

    private func scheduleAutosave(_ note: Note) {
        saveTasks[note.id]?.cancel()
        let id = note.id
        saveTasks[note.id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 s debounce
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, let current = self.notes.first(where: { $0.id == id }) else { return }
                self.save(current)
            }
        }
    }

    private func save(_ note: Note) {
        do {
            let data = try encoder.encode(note)
            lastLocalWrite = .now
            try data.write(to: fileURL(for: note.id), options: .atomic)
        } catch {
            NSLog("CloudNotes: failed to save note \(note.id): \(error)")
        }
        cloud?.push(note)
    }

    // MARK: - Account cloud sync (real-time)

    private func wireCloudHandlers() {
        cloud?.onRemoteUpsert = { [weak self] remote in
            guard let self else { return }
            if let idx = self.notes.firstIndex(where: { $0.id == remote.id }) {
                // Newest edit wins; never clobber a strictly newer local note.
                if remote.updatedAt > self.notes[idx].updatedAt {
                    self.notes[idx] = remote
                    self.writeLocalOnly(remote)
                }
            } else {
                self.notes.append(remote)
                self.writeLocalOnly(remote)
            }
        }
        cloud?.onRemoteDelete = { [weak self] id in
            guard let self else { return }
            guard self.notes.contains(where: { $0.id == id }) else { return }
            self.notes.removeAll { $0.id == id }
            self.lastLocalWrite = .now
            try? FileManager.default.removeItem(at: self.fileURL(for: id))
            if self.selectedNoteID == id { self.selectedNoteID = self.sortedNotes.first?.id }
        }
    }

    /// Writes a remote note to disk without echoing it back to the cloud.
    private func writeLocalOnly(_ note: Note) {
        if let data = try? encoder.encode(note) {
            lastLocalWrite = .now
            try? data.write(to: fileURL(for: note.id), options: .atomic)
        }
    }

    private func loadAll() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: syncFolder,
                                                      includingPropertiesForKeys: nil) else { return }
        var loaded: [Note] = []
        for url in files where url.pathExtension == "json" {
            if let data = try? Data(contentsOf: url),
               let note = try? decoder.decode(Note.self, from: data) {
                loaded.append(note)
            }
        }
        notes = loaded
    }

    // MARK: - External change monitoring (sync from other devices)

    private func startMonitoringFolder() {
        monitorFD = open(syncFolder.path, O_EVTONLY)
        guard monitorFD >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: monitorFD,
            eventMask: [.write],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            // Ignore events fired by our own writes (within 1 s).
            if Date.now.timeIntervalSince(self.lastLocalWrite) < 1.0 { return }
            self.mergeFromDisk()
        }
        source.resume()
        folderMonitor = source
    }

    /// Re-reads the folder and merges newer-on-disk notes without
    /// clobbering anything the user is actively editing.
    private func mergeFromDisk() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: syncFolder,
                                                      includingPropertiesForKeys: nil) else { return }
        var diskNotes: [UUID: Note] = [:]
        for url in files where url.pathExtension == "json" {
            if let data = try? Data(contentsOf: url),
               let note = try? decoder.decode(Note.self, from: data) {
                diskNotes[note.id] = note
            }
        }
        // Update or insert notes that are newer on disk.
        for (id, diskNote) in diskNotes {
            if let idx = notes.firstIndex(where: { $0.id == id }) {
                if diskNote.updatedAt > notes[idx].updatedAt {
                    notes[idx] = diskNote
                }
            } else {
                notes.append(diskNote)
            }
        }
        // Remove notes deleted elsewhere (but never one being edited right now).
        notes.removeAll { note in
            diskNotes[note.id] == nil && note.id != selectedNoteID
        }
    }
}
