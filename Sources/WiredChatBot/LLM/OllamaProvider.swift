// WiredChatBot — OllamaProvider.swift
// LLM provider for Ollama (local / self-hosted).
// API docs: https://github.com/ollama/ollama/blob/main/docs/api.md

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public class OllamaProvider: LLMProvider {
    public let name = "Ollama"

    public func complete(messages: [LLMMessage], config: LLMConfig) async throws -> String {
        let base = config.endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/api/chat") else {
            throw LLMError.invalidEndpoint(config.endpoint)
        }

        var req = URLRequest(url: url, timeoutInterval: config.timeoutSeconds)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": config.model,
            "stream": false,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "options": ["temperature": config.temperature, "num_predict": config.maxTokens]
        ]
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
            let message = json["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw LLMError.invalidResponse("Unexpected Ollama response shape")
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
