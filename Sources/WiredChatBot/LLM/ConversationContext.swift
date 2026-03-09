// WiredChatBot — ConversationContext.swift
// Per-user conversation history with temporal expiry, thread detection,
// and summarization support.

import Foundation

// MARK: - Single context (one user↔bot conversation)

public final class ConversationContext {
    private var history:             [LLMMessage] = []
    private var lastInteractionDate: Date          = .distantPast
    private let maxMessages:         Int
    private let lock =               NSLock()

    public init(maxMessages: Int) {
        self.maxMessages = maxMessages
    }

    // MARK: - Writing

    public func add(role: String, content: String) {
        lock.lock(); defer { lock.unlock() }
        history.append(LLMMessage(role: role, content: content))
        // Hard cap at 2× maxMessages so memory never grows unbounded even if
        // summarisation is disabled. Summarisation replaces this eviction.
        while history.count > maxMessages * 2 { history.removeFirst() }
    }

    public func recordAssistantResponse(_ text: String) {
        add(role: "assistant", content: text)
    }

    public func updateLastInteraction() {
        lock.lock(); defer { lock.unlock() }
        lastInteractionDate = Date()
    }

    public func clear() {
        lock.lock(); defer { lock.unlock() }
        history.removeAll()
        lastInteractionDate = .distantPast
    }

    // MARK: - Thread detection

    /// Returns true when the gap since the last interaction exceeds `seconds`,
    /// signalling that a new conversation thread has likely begun.
    /// Always false when `seconds` is 0 (feature disabled).
    public func isNewThread(timeoutSeconds: Double) -> Bool {
        guard timeoutSeconds > 0 else { return false }
        lock.lock(); defer { lock.unlock() }
        return Date().timeIntervalSince(lastInteractionDate) > timeoutSeconds
    }

    // MARK: - Summarisation

    /// Returns the oldest `maxMessages / 2` messages when the history is full,
    /// or nil when no summarisation is needed yet.
    public func messagesForSummarization() -> [LLMMessage]? {
        lock.lock(); defer { lock.unlock() }
        guard history.count >= maxMessages else { return nil }
        let count = maxMessages / 2
        return Array(history.prefix(count))
    }

    /// Replaces the oldest `count` messages with a single summary system message.
    /// No-op if history has fewer than `count` entries (race-condition guard).
    public func applySummary(_ summary: String, replacing count: Int) {
        lock.lock(); defer { lock.unlock() }
        guard history.count >= count else { return }
        history.removeFirst(count)
        history.insert(
            LLMMessage(role: "system",
                       content: "[Earlier conversation summary]: \(summary)"),
            at: 0
        )
    }

    // MARK: - Building the message array for LLM calls

    /// Constructs the full message list to send to the LLM.
    ///
    /// - Parameters:
    ///   - systemPrompt: Primary system prompt (bot identity, rules…).
    ///   - channelAwareness: Optional recent channel log injected as a secondary
    ///     system message so the bot knows what has been discussed around it.
    ///   - userInput: The current user turn (already formatted as "Nick: text").
    ///   - maxAgeSeconds: Drop history entries older than this. 0 = keep all.
    public func buildMessages(systemPrompt:      String,
                              channelAwareness:  String? = nil,
                              userInput:         String,
                              maxAgeSeconds:     Double  = 0) -> [LLMMessage] {
        lock.lock(); defer { lock.unlock() }

        var msgs = [LLMMessage(role: "system", content: systemPrompt)]

        if let awareness = channelAwareness, !awareness.isEmpty {
            msgs.append(LLMMessage(role: "system", content: awareness))
        }

        let cutoff: Date = maxAgeSeconds > 0
            ? Date().addingTimeInterval(-maxAgeSeconds)
            : .distantPast

        let filtered = history.filter { $0.timestamp > cutoff }
        msgs += filtered
        msgs.append(LLMMessage(role: "user", content: userInput))
        return msgs
    }
}

// MARK: - Manager: one context per (channel, user) pair or per DM user

public final class ConversationContextManager {
    private var contexts:    [String: ConversationContext] = [:]
    private let lock =       NSLock()
    private let maxMessages: Int

    public init(maxMessages: Int) {
        self.maxMessages = maxMessages
    }

    /// Returns (creating if needed) the context for the given key.
    ///
    /// Key conventions:
    ///   - Public channel: `"channel-<chatID>-<userID>"`
    ///   - Private DM:     `"private-<userID>"`
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
