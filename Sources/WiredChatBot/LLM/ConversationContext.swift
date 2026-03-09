// WiredChatBot — ConversationContext.swift
// Per-channel / per-user conversation history for LLM context.

import Foundation

// MARK: - Single context (one channel or one private conversation)

public final class ConversationContext {
    private var history:    [LLMMessage] = []
    private let maxMessages: Int
    private let lock = NSLock()

    public init(maxMessages: Int) {
        self.maxMessages = maxMessages
    }

    public func add(role: String, content: String) {
        lock.lock(); defer { lock.unlock() }
        history.append(LLMMessage(role: role, content: content))
        while history.count > maxMessages { history.removeFirst() }
    }

    /// Builds the full message array to send to the LLM, including system prompt
    /// and the new user turn.
    public func buildMessages(systemPrompt: String, userInput: String) -> [LLMMessage] {
        lock.lock(); defer { lock.unlock() }
        var msgs = [LLMMessage(role: "system", content: systemPrompt)]
        msgs += history
        msgs.append(LLMMessage(role: "user", content: userInput))
        return msgs
    }

    public func recordAssistantResponse(_ text: String) {
        add(role: "assistant", content: text)
    }

    public func clear() {
        lock.lock(); defer { lock.unlock() }
        history.removeAll()
    }
}

// MARK: - Manager: one context per channel / per user DM

public final class ConversationContextManager {
    private var contexts: [String: ConversationContext] = [:]
    private let lock = NSLock()
    private let maxMessages: Int

    public init(maxMessages: Int) {
        self.maxMessages = maxMessages
    }

    /// Returns (creating if needed) the context for the given key.
    /// Key convention: "channel-<chatID>" or "private-<nick>"
    public func context(for key: String) -> ConversationContext {
        lock.lock(); defer { lock.unlock() }
        if let ctx = contexts[key] { return ctx }
        let ctx = ConversationContext(maxMessages: maxMessages)
        contexts[key] = ctx
        return ctx
    }

    public func clearContext(for key: String) {
        lock.lock(); defer { lock.unlock() }
        contexts.removeValue(forKey: key)
    }

    public func clearAll() {
        lock.lock(); defer { lock.unlock() }
        contexts.removeAll()
    }
}
