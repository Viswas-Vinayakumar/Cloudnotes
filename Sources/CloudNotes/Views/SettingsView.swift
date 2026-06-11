import SwiftUI

/// Settings (⌘,): AI provider (free local Ollama by default), model,
/// and a peek at the sync folder.
struct SettingsView: View {
    @EnvironmentObject private var store: NotesStore
    @AppStorage("aiProvider") private var provider: String = AIProvider.ollama.rawValue
    @AppStorage("ollamaURL") private var ollamaURL: String = AIService.defaultOllamaURL
    @AppStorage("ollamaModel") private var ollamaModel: String = AIService.defaultOllamaModel
    @AppStorage("anthropicAPIKey") private var apiKey: String = ""
    @AppStorage("anthropicModel") private var anthropicModel: String = AIService.defaultAnthropicModel

    var body: some View {
        Form {
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

            Section("Sync") {
                LabeledContent("Mode", value: store.isUsingiCloud ? "iCloud Drive" : "Local folder")
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
        .formStyle(.grouped)
        .frame(width: 480)
        .padding()
    }
}
