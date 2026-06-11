import SwiftUI

/// Three-pane layout in the style of a classic macOS notes app:
/// sidebar (folders) → notes list → editor, with a unified toolbar.
struct ContentView: View {
    @EnvironmentObject private var store: NotesStore
    @EnvironmentObject private var cloud: CloudSyncManager
    @State private var aiRunning = false
    @State private var aiError: String?

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 150, ideal: 170, max: 220)
        } content: {
            NoteListView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            EditorView(aiRunning: $aiRunning)
        }
        .tint(.yellow)
        .toolbar { toolbarContent }
        .searchable(text: $store.searchText, placement: .toolbar, prompt: "Search")
        .alert("AI Cleanup", isPresented: .init(
            get: { aiError != nil },
            set: { if !$0 { aiError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(aiError ?? "")
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List {
            Section("iCloud") {
                Label {
                    HStack {
                        Text("Notes")
                        Spacer()
                        Text("\(store.notes.count)")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    }
                } icon: {
                    Image(systemName: "folder")
                        .foregroundStyle(.yellow)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 6) {
                if cloud.isSignedIn {
                    Image(systemName: cloud.isSyncing ? "arrow.triangle.2.circlepath.icloud" : "checkmark.icloud.fill")
                        .foregroundStyle(.green)
                    Text(cloud.isSyncing ? "Syncing…" : (cloud.userEmail ?? "Synced"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Image(systemName: store.locationLabel == "Local folder" ? "externaldrive" : "checkmark.icloud")
                        .foregroundStyle(.secondary)
                    Text(store.locationLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(8)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                store.createNote()
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .help("New note (⌘N)")
        }

        ToolbarItemGroup {
            Button {
                if let id = store.selectedNoteID { store.appendTimestamp(to: id) }
            } label: {
                Image(systemName: "clock")
            }
            .help("Insert timestamp (⇧⌘T)")
            .disabled(store.selectedNoteID == nil)

            Button {
                runAICleanup()
            } label: {
                if aiRunning {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "sparkles")
                }
            }
            .help("AI: turn rough notes into proper notes")
            .disabled(store.selectedNote?.isEmpty != false || aiRunning)

            if store.selectedNote?.preAIContent != nil {
                Button {
                    if let id = store.selectedNoteID { store.revertAIResult(for: id) }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .help("Revert AI cleanup")
            }

            Button(role: .destructive) {
                if let id = store.selectedNoteID { store.deleteNote(id) }
            } label: {
                Image(systemName: "trash")
            }
            .help("Delete note")
            .disabled(store.selectedNoteID == nil)
        }
    }

    // MARK: - AI

    private func runAICleanup() {
        guard let note = store.selectedNote, !note.isEmpty else { return }
        aiRunning = true
        let id = note.id
        let content = note.content
        Task {
            do {
                let cleaned = try await AIService.cleanUp(noteContent: content)
                await MainActor.run {
                    store.applyAIResult(cleaned, to: id)
                    aiRunning = false
                }
            } catch {
                await MainActor.run {
                    aiError = error.localizedDescription
                    aiRunning = false
                }
            }
        }
    }
}
