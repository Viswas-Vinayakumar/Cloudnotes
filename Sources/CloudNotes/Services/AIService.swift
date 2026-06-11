import Foundation

enum AIServiceError: LocalizedError {
    case missingAPIKey
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No API key set. Add your Anthropic API key in Settings (⌘,)."
        case .badResponse(let detail):
            return "AI request failed: \(detail)"
        }
    }
}

/// Talks to the Anthropic Messages API to turn rough, fragmented notes
/// into clean, structured notes — while keeping every fact and timestamp.
struct AIService {
    static let defaultModel = "claude-sonnet-4-6"

    static func cleanUp(noteContent: String) async throws -> String {
        let defaults = UserDefaults.standard
        guard let apiKey = defaults.string(forKey: "anthropicAPIKey"),
              !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw AIServiceError.missingAPIKey
        }
        let model = defaults.string(forKey: "anthropicModel") ?? defaultModel

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let system = """
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

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4000,
            "system": system,
            "messages": [
                ["role": "user", "content": noteContent]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AIServiceError.badResponse("No HTTP response.")
        }
        guard http.statusCode == 200 else {
            let detail = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
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

        guard !text.isEmpty else {
            throw AIServiceError.badResponse("Empty response from model.")
        }
        return text
    }
}
