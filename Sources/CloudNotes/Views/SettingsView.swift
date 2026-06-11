import SwiftUI

/// Settings (⌘,): Anthropic API key, model, and a peek at the sync folder.
struct SettingsView: View {
    @EnvironmentObject private var store: NotesStore
    @AppStorage("anthropicAPIKey") private var apiKey: String = ""
    @AppStorage("anthropicModel") private var model: String = AIService.defaultModel

    var body: some View {
        Form {
            Section("AI Cleanup") {
                SecureField("Anthropic API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                TextField("Model", text: $model)
                    .textFieldStyle(.roundedBorder)
                Text("Get a key at console.anthropic.com. It is stored only on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .frame(width: 460)
        .padding()
    }
}
