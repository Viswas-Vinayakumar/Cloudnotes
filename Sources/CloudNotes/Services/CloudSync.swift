import Foundation
import Supabase

/// Account-based real-time sync. Sign in with email + password; every change
/// is pushed to a `notes` table and a realtime subscription streams in
/// changes made on any other device, live.
///
/// Backend: a free Supabase project (URL + anon key set in Settings).
/// The table schema lives in `supabase/schema.sql` in this repo.
@MainActor
final class CloudSyncManager: ObservableObject {
    @Published private(set) var userEmail: String?
    @Published private(set) var statusText: String = "Not signed in"
    @Published private(set) var isSyncing = false

    /// NotesStore plugs in here to receive remote changes.
    var onRemoteUpsert: ((Note) -> Void)?
    var onRemoteDelete: ((UUID) -> Void)?

    private var client: SupabaseClient?
    private var channel: RealtimeChannelV2?
    private var listenTasks: [Task<Void, Never>] = []
    private var pushTasks: [UUID: Task<Void, Never>] = [:]

    var isSignedIn: Bool { userEmail != nil }

    var isConfigured: Bool {
        let d = UserDefaults.standard
        return !(d.string(forKey: "supabaseURL") ?? "").isEmpty
            && !(d.string(forKey: "supabaseAnonKey") ?? "").isEmpty
    }

    // MARK: - Row shape (matches supabase/schema.sql)

    private struct NoteRow: Codable {
        var id: UUID
        var user_id: UUID?
        var content: String
        var pre_ai_content: String?
        var created_at: Date
        var updated_at: Date
        var deleted: Bool

        init(note: Note, userID: UUID) {
            id = note.id
            user_id = userID
            content = note.content
            pre_ai_content = note.preAIContent
            created_at = note.createdAt
            updated_at = note.updatedAt
            deleted = false
        }

        var asNote: Note {
            Note(id: id, content: content, createdAt: created_at,
                 updatedAt: updated_at, preAIContent: pre_ai_content)
        }
    }

    private static let jsonDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso.date(from: s) { return date }
            iso.formatOptions = [.withInternetDateTime]
            if let date = iso.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Bad date: \(s)"))
        }
        return d
    }()

    // MARK: - Lifecycle

    /// Builds the client from Settings and restores a previous session if any.
    func bootstrap() async {
        guard isConfigured else { return }
        let d = UserDefaults.standard
        guard let url = URL(string: d.string(forKey: "supabaseURL") ?? ""),
              let key = d.string(forKey: "supabaseAnonKey") else { return }
        client = SupabaseClient(supabaseURL: url, supabaseKey: key)
        if let session = try? await client?.auth.session {
            userEmail = session.user.email
            statusText = "Signed in as \(session.user.email ?? "account")"
            await startRealtime()
            await pullAll()
        }
    }

    func signIn(email: String, password: String) async throws {
        guard isConfigured else {
            throw NSError(domain: "CloudNotes", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Add your Supabase URL and anon key in Settings first."
            ])
        }
        if client == nil { await bootstrap() }
        guard let client else { return }
        let session = try await client.auth.signIn(email: email, password: password)
        userEmail = session.user.email
        statusText = "Signed in as \(session.user.email ?? "account")"
        await startRealtime()
        await pullAll()
    }

    func signUp(email: String, password: String) async throws {
        if client == nil { await bootstrap() }
        guard let client else { return }
        _ = try await client.auth.signUp(email: email, password: password)
        // If email confirmation is disabled in Supabase, this signs straight in.
        if let session = try? await client.auth.session {
            userEmail = session.user.email
            statusText = "Signed in as \(session.user.email ?? "account")"
            await startRealtime()
            await pullAll()
        } else {
            statusText = "Check your email to confirm, then sign in."
        }
    }

    func signOut() async {
        listenTasks.forEach { $0.cancel() }
        listenTasks.removeAll()
        if let channel { await client?.removeChannel(channel) }
        channel = nil
        try? await client?.auth.signOut()
        userEmail = nil
        statusText = "Not signed in"
    }

    // MARK: - Push (local → cloud), debounced per note

    func push(_ note: Note) {
        guard isSignedIn else { return }
        pushTasks[note.id]?.cancel()
        pushTasks[note.id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await self?.upsertNow(note)
        }
    }

    func pushDelete(_ id: UUID) {
        guard isSignedIn, let client else { return }
        Task {
            do {
                try await client.from("notes")
                    .update(["deleted": true])
                    .eq("id", value: id)
                    .execute()
            } catch {
                NSLog("CloudNotes sync: delete push failed: \(error)")
            }
        }
    }

    private func upsertNow(_ note: Note) async {
        guard let client else { return }
        do {
            isSyncing = true
            let uid = try await client.auth.session.user.id
            let row = NoteRow(note: note, userID: uid)
            try await client.from("notes").upsert(row).execute()
            isSyncing = false
        } catch {
            isSyncing = false
            NSLog("CloudNotes sync: push failed: \(error)")
            statusText = "Sync error — will retry on next edit"
        }
    }

    // MARK: - Pull (cloud → local)

    private func pullAll() async {
        guard let client else { return }
        do {
            let rows: [NoteRow] = try await client.from("notes")
                .select()
                .execute()
                .value
            for row in rows {
                if row.deleted {
                    onRemoteDelete?(row.id)
                } else {
                    onRemoteUpsert?(row.asNote)
                }
            }
        } catch {
            NSLog("CloudNotes sync: initial pull failed: \(error)")
        }
    }

    // MARK: - Realtime (live changes from other devices)

    private func startRealtime() async {
        guard let client, channel == nil else { return }
        guard let uid = try? await client.auth.session.user.id else { return }

        let ch = client.channel("notes-sync")
        let inserts = ch.postgresChange(InsertAction.self, schema: "public",
                                        table: "notes",
                                        filter: "user_id=eq.\(uid.uuidString)")
        let updates = ch.postgresChange(UpdateAction.self, schema: "public",
                                        table: "notes",
                                        filter: "user_id=eq.\(uid.uuidString)")
        await ch.subscribe()
        channel = ch

        listenTasks.append(Task { [weak self] in
            for await action in inserts {
                guard let self else { return }
                if let row = try? action.decodeRecord(as: NoteRow.self,
                                                      decoder: Self.jsonDecoder) {
                    await MainActor.run { self.handleRemote(row) }
                }
            }
        })
        listenTasks.append(Task { [weak self] in
            for await action in updates {
                guard let self else { return }
                if let row = try? action.decodeRecord(as: NoteRow.self,
                                                      decoder: Self.jsonDecoder) {
                    await MainActor.run { self.handleRemote(row) }
                }
            }
        })
    }

    private func handleRemote(_ row: NoteRow) {
        if row.deleted {
            onRemoteDelete?(row.id)
        } else {
            onRemoteUpsert?(row.asNote)
        }
    }
}
