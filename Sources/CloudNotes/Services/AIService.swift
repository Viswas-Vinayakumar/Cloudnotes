import Foundation

enum AIProvider: String, CaseIterable, Identifiable {
    case ollama    // free, local, default
    case anthropic // optional, uses your API key

    var id: String { rawValue }
    var label: String {
        switch self {
        case .ollama: return "Local — Ollama (free)"
        case .anthropic: return "Anthropic API"
        }
    }
}

enum AIServiceError: LocalizedError {
    case missingAPIKey
    case ollamaUnreachable
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No API key set. Add your Anthropic API key in Settings (⌘,), or switch to the free local provider."
        case .ollamaUnreachable:
            return """
            Couldn't reach Ollama at localhost:11434.

            Install & start it (free, one time):
              brew install ollama
              ollama pull llama3.2
              ollama serve
            """
        case .badResponse(let detail):
            return "AI request failed: \(detail)"
        }
    }
}

/// Turns rough, fragmented notes into clean, structured notes — keeping
/// every fact and timestamp. Default: free local model via Ollama.
struct AIService {
    static let defaultOllamaModel = "llama3.2"
    static let defaultOllamaURL = "http://localhost:11434"
    static let defaultAnthropicModel = "claude-sonnet-4-6"

    static let systemPrompt = """
    You clean up rough personal notes. Rewrite the user's raw note into clear, \
    well-organized plain text the author can refer back to later.

    Rules:
    - Fix spelling, grammar, and fragments into proper sentences.
    - Keep ALL information; never invent facts or drop details.
    - Preserve any timestamp lines like [11 June 2026, 2:20 PM] exactly where they are.
    - Keep the first line as the note's title.
    - Use simple dashes for lists, short headings where helpful.
    - Output ONLY the cleaned note text. No preamble, no commentary, no code fences.
    """

    static func cleanUp(noteContent: String) async throws -> String {
        let defaults = UserDefaults.standard
        let provider = AIProvider(rawValue: defaults.string(forKey: "aiProvider") ?? "") ?? .ollama
        switch provider {
        case .ollama:
            return try await cleanUpWithOllama(noteContent)
        case .anthropic:
            return try await cleanUpWithAnthropic(noteContent)
        }
    }

    // MARK: - Ollama (free, local)

    private static func cleanUpWithOllama(_ noteContent: String) async throws -> String {
        let defaults = UserDefaults.standard
        let base = defaults.string(forKey: "ollamaURL") ?? defaultOllamaURL
        let model = defaults.string(forKey: "ollamaModel") ?? defaultOllamaModel
        guard let url = URL(string: "\(base)/api/chat") else {
            throw AIServiceError.badResponse("Invalid Ollama URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120

        let body: [String: Any] = [
            "model": model,
            "stream": false,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": noteContent]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AIServiceError.ollamaUnreachable
        }

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let detail = String(data: data, encoding: .utf8) ?? "Unknown Ollama error"
            throw AIServiceError.badResponse(detail)
        }

        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let message = json["message"] as? [String: Any],
            let text = message["content"] as? String,
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw AIServiceError.badResponse("Unexpected Ollama response shape.")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Anthropic (optional)

    private static func cleanUpWithAnthropic(_ noteContent: String) async throws -> String {
        let defaults = UserDefaults.standard
        guard let apiKey = defaults.string(forKey: "anthropicAPIKey"),
              !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw AIServiceError.missingAPIKey
        }
        let model = defaults.string(forKey: "anthropicModel") ?? defaultAnthropicModel

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4000,
            "system": systemPrompt,
            "messages": [["role": "user", "content": noteContent]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let detail = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIServiceError.badResponse(detail)
        }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = json["content"] as? [[String: Any]]
        else {
            throw AIServiceError.badResponse("Unexpected response shape.")
        }
        let text = content
            .filter { ($0["type"] as? String) == "text" }
            .compactMap { $0["text"] as? String }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AIServiceError.badResponse("Empty response from model.") }
        return text
    }
}
