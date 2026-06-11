import SwiftUI

/// Settings (⌘,): account sign-in for real-time cloud sync,
/// AI provider (free local Ollama by default), and sync folder info.
struct SettingsView: View {
    @EnvironmentObject private var store: NotesStore
    @EnvironmentObject private var cloud: CloudSyncManager

    // Account / cloud sync
    @AppStorage("supabaseURL") private var supabaseURL: String = ""
    @AppStorage("supabaseAnonKey") private var supabaseAnonKey: String = ""
    @State private var email = ""
    @State private var password = ""
    @State private var authBusy = false
    @State private var authError: String?

    // AI
    @AppStorage("aiProvider") private var provider: String = AIProvider.ollama.rawValue
    @AppStorage("ollamaURL") private var ollamaURL: String = AIService.defaultOllamaURL
    @AppStorage("ollamaModel") private var ollamaModel: String = AIService.defaultOllamaModel
    @AppStorage("anthropicAPIKey") private var apiKey: String = ""
    @AppStorage("anthropicModel") private var anthropicModel: String = AIService.defaultAnthropicModel

    var body: some View {
        Form {
            accountSection
            aiSection
            folderSection
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .padding()
    }

    // MARK: - Account (real-time cloud sync)

    private var accountSection: some View {
        Section("Account — Real-Time Cloud Sync") {
            if cloud.isSignedIn {
                LabeledContent("Status", value: cloud.statusText)
                Button("Sign Out", role: .destructive) {
                    Task { await cloud.signOut() }
                }
            } else {
                TextField("Supabase project URL", text: $supabaseURL,
                          prompt: Text("https://xxxx.supabase.co"))
                    .textFieldStyle(.roundedBorder)
                SecureField("Supabase anon key", text: $supabaseAnonKey)
                    .textFieldStyle(.roundedBorder)
                Divider()
                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Sign In") { auth { try await cloud.signIn(email: email, password: password) } }
                        .keyboardShortcut(.defaultAction)
                    Button("Create Account") { auth { try await cloud.signUp(email: email, password: password) } }
                    if authBusy { ProgressView().controlSize(.small) }
                }
                .disabled(email.isEmpty || password.isEmpty || authBusy)
                if let authError {
                    Text(authError).font(.caption).foregroundStyle(.red)
                }
                Text("""
                Signed-in sync is instant across all your Macs (free Supabase tier). \
                One-time backend setup: create a free project at supabase.com, run \
                supabase/schema.sql from this repo in its SQL editor, then paste the \
                project URL and anon key above. Without an account, notes still \
                auto-sync through your iCloud Drive folder.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func auth(_ op: @escaping () async throws -> Void) {
        authBusy = true
        authError = nil
        Task {
            do { try await op() }
            catch { authError = error.localizedDescription }
            authBusy = false
        }
    }

    // MARK: - AI

    private var aiSection: some View {
        Section("AI Cleanup") {
            Picker("Provider", selection: $provider) {
                ForEach(AIProvider.allCases) { p in
                    Text(p.label).tag(p.rawValue)
                }
            }
            .pickerStyle(.radioGroup)

            if provider == AIProvider.ollama.rawValue {
                TextField("Model", text: $ollamaModel)
                    .textFieldStyle(.roundedBorder)
                TextField("Server", text: $ollamaURL)
                    .textFieldStyle(.roundedBorder)
                Text("""
                Free & private — runs on this Mac, no tokens, works offline.
                One-time setup in Terminal:
                  brew install ollama
                  ollama pull llama3.2
                  ollama serve
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                SecureField("Anthropic API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                TextField("Model", text: $anthropicModel)
                    .textFieldStyle(.roundedBorder)
                Text("Uses paid API tokens. Key is stored only on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Local folder

    private var folderSection: some View {
        Section("Offline Storage") {
            LabeledContent("Folder mode", value: store.isUsingiCloud ? "iCloud Drive" : "Local folder")
            LabeledContent("Folder") {
                Text(store.syncFolder.path)
                    .font(.caption)
                    .textSelection(.enabled)
            }
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([store.syncFolder])
            }
        }
    }
}
