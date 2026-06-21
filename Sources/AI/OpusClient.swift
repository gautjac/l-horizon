import Foundation

/// A thin Anthropic Messages-API client built around forced tool use, so every
/// response comes back as a validated JSON object instead of free text.
///
/// API key resolution (in order, never hardcoded):
///   1. the `CLAUDE_API_KEY` environment variable
///   2. the file `~/.horizon/config` (its whole trimmed contents = the key)
/// If neither is present the AI features are disabled and the app still works
/// fully for manual planning.
///
/// Per the model's constraints: forced-JSON via tool_choice, NO `thinking`, and
/// `temperature` is omitted (opus rejects it).
enum OpusClient {
    static let model = "claude-opus-4-8"
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    struct Tool {
        let name: String
        let description: String
        let inputSchema: [String: Any]
    }

    enum OpusError: LocalizedError {
        case noKey
        case http(Int, String)
        case badResponse
        case noToolUse

        var errorDescription: String? {
            switch self {
            case .noKey:
                return "Aucune clé Anthropic. Ajoutez-en une dans ~/.horizon/config."
            case .http(let code, let body):
                return "HTTP \(code): \(body.prefix(300))"
            case .badResponse:
                return "Réponse inattendue de l'API."
            case .noToolUse:
                return "Le modèle n'a renvoyé aucun résultat structuré."
            }
        }
    }

    /// Resolve the key from env or ~/.horizon/config. Returns nil when absent.
    static func resolveKey() -> String? {
        if let env = ProcessInfo.processInfo.environment["CLAUDE_API_KEY"],
           !env.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return env.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let path = (NSHomeDirectory() as NSString).appendingPathComponent(".horizon/config")
        if let contents = try? String(contentsOfFile: path, encoding: .utf8) {
            let key = contents.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty { return key }
        }
        return nil
    }

    /// True when an AI call can be attempted. Cheap; safe to call from the UI to
    /// decide whether to show the "ajoutez votre clé" note.
    static var hasKey: Bool { resolveKey() != nil }

    /// Run one forced-tool call and return the tool input as a parsed dictionary.
    static func runTool(system: String, userText: String,
                        tool: Tool, maxTokens: Int = 4096) async throws -> [String: Any] {
        guard let key = resolveKey() else { throw OpusError.noKey }

        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": [["role": "user", "content": [["type": "text", "text": userText]]]],
            "tools": [[
                "name": tool.name,
                "description": tool.description,
                "input_schema": tool.inputSchema,
            ]],
            "tool_choice": ["type": "tool", "name": tool.name],
        ]

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw OpusError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw OpusError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let blocks = json["content"] as? [[String: Any]] else { throw OpusError.badResponse }
        for block in blocks where block["type"] as? String == "tool_use" {
            if let input = block["input"] as? [String: Any] { return input }
        }
        throw OpusError.noToolUse
    }
}
