// WiredChatBot — AnthropicProvider.swift
// Anthropic Claude API provider.
// Docs: https://docs.anthropic.com/en/api/messages

import Foundation

public class AnthropicProvider: LLMProvider {
    public let name = "Anthropic"

    private static let apiURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let apiVersion = "2023-06-01"

    public func complete(messages: [LLMMessage], config: LLMConfig) async throws -> String {
        guard let apiKey = config.apiKey, !apiKey.isEmpty else {
            throw LLMError.missingApiKey
        }

        var req = URLRequest(url: Self.apiURL, timeoutInterval: config.timeoutSeconds)
        req.httpMethod = "POST"
        req.setValue("application/json",   forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey,               forHTTPHeaderField: "x-api-key")
        req.setValue(Self.apiVersion,      forHTTPHeaderField: "anthropic-version")

        // Separate system message from conversation turns
        var systemContent: String? = nil
        var turns: [[String: Any]] = []

        for msg in messages {
            if msg.role == "system" {
                systemContent = msg.content
            } else {
                turns.append(["role": msg.role, "content": msg.content])
            }
        }

        var body: [String: Any] = [
            "model":      config.model,
            "max_tokens": config.maxTokens,
            "messages":   turns,
        ]
        if let system = systemContent { body["system"] = system }

        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)

        guard let http = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse("Not an HTTP response")
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LLMError.httpError(http.statusCode, body)
        }

        guard
            let json    = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let content = json["content"] as? [[String: Any]],
            let block   = content.first,
            block["type"] as? String == "text",
            let text    = block["text"] as? String
        else {
            throw LLMError.invalidResponse("Unexpected Anthropic response shape")
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
