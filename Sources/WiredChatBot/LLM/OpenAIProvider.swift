// WiredChatBot — OpenAIProvider.swift
// OpenAI-compatible LLM provider.
// Works with OpenAI, LM Studio, Groq, Mistral, Ollama (openai-compat), etc.
// Set `endpoint` to the base URL (e.g. http://localhost:1234 for LM Studio).

import Foundation

public class OpenAIProvider: LLMProvider {
    public let name = "OpenAI-compatible"

    public func complete(messages: [LLMMessage], config: LLMConfig) async throws -> String {
        let base = config.endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/v1/chat/completions") else {
            throw LLMError.invalidEndpoint(config.endpoint)
        }

        var req = URLRequest(url: url, timeoutInterval: config.timeoutSeconds)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let key = config.apiKey, !key.isEmpty {
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "model":       config.model,
            "messages":    messages.map { ["role": $0.role, "content": $0.content] },
            "max_tokens":  config.maxTokens,
            "temperature": config.temperature,
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
            let choices = json["choices"] as? [[String: Any]],
            let first   = choices.first,
            let message = first["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw LLMError.invalidResponse("Unexpected OpenAI response shape")
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
