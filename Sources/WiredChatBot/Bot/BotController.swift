// WiredChatBot — BotController.swift
// Core coordinator: manages the Wired connection, event handlers, LLM calls,
// rate limiting, reconnection, and user tracking.
// Designed to be observable from SwiftUI (all state mutations on main queue).

import Foundation
import WiredSwift

// MARK: - Errors

public enum BotError: Error, LocalizedError {
    case specLoadFailed(String)
    case connectionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .specLoadFailed(let p):  return "Cannot load protocol spec from: \(p)"
        case .connectionFailed(let e): return "Connection failed: \(e)"
        }
    }
}

// MARK: - BotController

public final class BotController: NSObject {

    // MARK: Public config / services (read from SwiftUI wrapper if needed)
    public let config:      BotConfig
    public let triggerEngine: TriggerEngine
    public let contextManager: ConversationContextManager
    public private(set) var llmProvider: LLMProvider?

    // MARK: Event handlers
    public let chatHandler:  ChatEventHandler  = ChatEventHandler()
    public let userHandler:  UserEventHandler  = UserEventHandler()
    public let fileHandler:  FileEventHandler  = FileEventHandler()
    public let boardHandler: BoardEventHandler = BoardEventHandler()

    // MARK: Private state
    private var connection:       Connection?
    private var spec:             P7Spec?
    private var eventDispatcher:  EventDispatcher!
    private var isRunning:        Bool = false
    private var reconnectAttempts: Int = 0

    // Rate limiting
    private var lastResponseDate: Date = .distantPast

    // userID -> nick, per channel
    private var channelUsers: [UInt32: [UInt32: String]] = [:]

    // MARK: - Init

    public init(config: BotConfig) {
        self.config         = config
        self.triggerEngine  = TriggerEngine(triggers: config.triggers)
        self.contextManager = ConversationContextManager(maxMessages: config.llm.contextMessages)
        self.llmProvider    = LLMProviderFactory.create(from: config.llm)
        super.init()
        self.eventDispatcher = EventDispatcher(bot: self)
    }

    // MARK: - Lifecycle

    /// Start the bot. Blocks on RunLoop.main until `stop()` is called.
    public func start(specPath: String) throws {
        guard let loadedSpec = P7Spec(withUrl: URL(fileURLWithPath: specPath)) else {
            throw BotError.specLoadFailed(specPath)
        }
        self.spec = loadedSpec
        self.isRunning = true

        try connectToServer()
        RunLoop.main.run()
    }

    public func stop() {
        isRunning = false
        connection?.disconnect()
    }

    // MARK: - Connection management

    private func connectToServer() throws {
        guard let spec = spec else { return }

        let conn = Connection(withSpec: spec)
        conn.addDelegate(eventDispatcher)
        conn.clientInfoDelegate = self
        conn.nick   = config.identity.nick
        conn.status = config.identity.status
        if let icon = config.identity.icon { conn.icon = icon }

        self.connection = conn

        let url = Url(withString: config.server.url)
        BotLogger.info("Connecting to \(url.urlString())…")
        try conn.connect(withUrl: url)
    }

    public func handleLogin(connection: Connection) {
        BotLogger.info("Logged in as '\(config.identity.nick)' (userID: \(connection.userID ?? 0))")
        reconnectAttempts = 0
        for chatID in config.server.channels {
            BotLogger.info("Joining channel \(chatID)…")
            _ = connection.joinChat(chatID: chatID)
        }
    }

    public func handleDisconnect(error: Error?) {
        guard isRunning else { return }
        let maxAttempts = config.server.maxReconnectAttempts
        if maxAttempts > 0, reconnectAttempts >= maxAttempts {
            BotLogger.error("Max reconnect attempts reached. Stopping.")
            stop()
            return
        }
        reconnectAttempts += 1
        let delay = config.server.reconnectDelay
        BotLogger.info("Reconnecting in \(Int(delay))s (attempt \(reconnectAttempts))…")
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.isRunning else { return }
            do {
                try self.connectToServer()
            } catch {
                BotLogger.error("Reconnect failed: \(error.localizedDescription)")
                self.handleDisconnect(error: error)
            }
        }
    }

    // MARK: - Sending messages

    /// Send a chat message with rate limiting and length truncation.
    public func sendChat(_ text: String, to chatID: UInt32) {
        guard let connection, connection.isConnected() else { return }

        let elapsed = Date().timeIntervalSince(lastResponseDate)
        let limit   = config.behavior.rateLimitSeconds

        if elapsed < limit {
            DispatchQueue.main.asyncAfter(deadline: .now() + (limit - elapsed)) { [weak self] in
                self?.sendChatNow(text, to: chatID)
            }
        } else {
            sendChatNow(text, to: chatID)
        }
    }

    private func sendChatNow(_ text: String, to chatID: UInt32) {
        guard let connection, let spec, connection.isConnected() else { return }

        let maxLen = config.behavior.maxResponseLength
        let body   = text.count > maxLen ? String(text.prefix(maxLen - 1)) + "…" : text

        let msg = P7Message(withName: "wired.chat.send_say", spec: spec)
        msg.addParameter(field: "wired.chat.id",  value: chatID)
        msg.addParameter(field: "wired.chat.say", value: body)
        _ = connection.send(message: msg)
        lastResponseDate = Date()
    }

    // MARK: - LLM dispatch

    /// Sends `input` to the LLM asynchronously and posts the reply to `chatID`.
    public func dispatchLLM(input: String, nick: String, chatID: UInt32, isPrivate: Bool) {
        guard let llm = llmProvider else {
            BotLogger.warning("No LLM provider configured; ignoring message")
            return
        }

        let ctxKey  = isPrivate ? "private-\(nick)" : "channel-\(chatID)"
        let ctx     = contextManager.context(for: ctxKey)
        let system  = buildSystemPrompt()
        let userTurn = "\(nick): \(input)"
        let messages = ctx.buildMessages(systemPrompt: system, userInput: userTurn)

        Task {
            do {
                let reply = try await llm.complete(messages: messages, config: self.config.llm)
                ctx.add(role: "user", content: userTurn)
                ctx.recordAssistantResponse(reply)
                await MainActor.run { self.sendChat(reply, to: chatID) }
            } catch {
                BotLogger.error("LLM error: \(error.localizedDescription)")
            }
        }
    }

    private func buildSystemPrompt() -> String {
        var prompt = config.llm.systemPrompt
        if let info = connection?.serverInfo, let name = info.serverName {
            prompt += "\n\nServer: \(name)"
        }
        prompt += "\nYour nick: \(config.identity.nick)"
        return prompt
    }

    // MARK: - User tracking

    public func setNick(_ nick: String, forUser userID: UInt32, in chatID: UInt32) {
        if channelUsers[chatID] == nil { channelUsers[chatID] = [:] }
        channelUsers[chatID]?[userID] = nick
    }

    public func removeUser(_ userID: UInt32, from chatID: UInt32) {
        channelUsers[chatID]?.removeValue(forKey: userID)
    }

    public func nick(ofUser userID: UInt32, in chatID: UInt32) -> String? {
        channelUsers[chatID]?[userID]
    }

    // MARK: - Filtering helpers

    public func isMentioned(in text: String) -> Bool {
        let lower   = text.lowercased()
        let botNick = config.identity.nick.lowercased()
        if lower.contains(botNick) { return true }
        return config.behavior.mentionKeywords.contains { lower.contains($0.lowercased()) }
    }

    public func shouldIgnore(nick: String) -> Bool {
        if nick == config.identity.nick, config.behavior.ignoreOwnMessages { return true }
        return config.behavior.ignoredNicks.contains(nick)
    }
}

// MARK: - ClientInfoDelegate

extension BotController: ClientInfoDelegate {
    public func clientInfoApplicationName(for connection: Connection) -> String? { "WiredChatBot" }
    public func clientInfoApplicationVersion(for connection: Connection) -> String? { "1.0" }
    public func clientInfoApplicationBuild(for connection: Connection) -> String? { "1" }
}
