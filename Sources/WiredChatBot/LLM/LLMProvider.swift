// WiredChatBot — LLMProvider.swift
// Protocol definition and factory for LLM backends.

import Foundation

// MARK: - Message model

public struct LLMMessage {
    public let role: String  // "system" | "user" | "assistant"
    public let content: String
    /// Wall-clock time when this message was added. Used for temporal expiry.
    public let timestamp: Date

    public init(role: String, content: String, timestamp: Date = Date()) {
        self.role      = role
        self.content   = content
        self.timestamp = timestamp
    }
}

// MARK: - Error

public enum LLMError: Error, LocalizedError {
    case invalidEndpoint(String)
    case networkError(Error)
    case httpError(Int, String)
    case invalidResponse(String)
    case missingApiKey

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint(let u):  return "Invalid endpoint: \(u)"
        case .networkError(let e):     return "Network error: \(e.localizedDescription)"
        case .httpError(let c, let b): return "HTTP \(c): \(b)"
        case .invalidResponse(let m):  return "Invalid response: \(m)"
        case .missingApiKey:           return "API key required but not set"
        }
    }
}

// MARK: - Protocol

public protocol LLMProvider {
    var name: String { get }
    func complete(messages: [LLMMessage], config: LLMConfig) async throws -> String
}

// MARK: - Factory

public enum LLMProviderFactory {
    public static func create(from config: LLMConfig) -> LLMProvider? {
        switch config.provider.lowercased() {
        case "ollama":
            return OllamaProvider()
        case "openai", "openai-compatible", "lmstudio", "groq", "mistral":
            return OpenAIProvider()
        case "anthropic", "claude":
            return AnthropicProvider()
        default:
            return nil
        }
    }
}
