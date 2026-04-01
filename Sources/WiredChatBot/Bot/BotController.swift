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
    public let config: BotConfig
    public let triggerEngine: TriggerEngine
    public let contextManager: ConversationContextManager
    public private(set) var llmProvider: LLMProvider?

    // MARK: Event handlers
    public let chatHandler: ChatEventHandler  = ChatEventHandler()
    public let userHandler: UserEventHandler  = UserEventHandler()
    public let fileHandler: FileEventHandler  = FileEventHandler()
    public let boardHandler: BoardEventHandler = BoardEventHandler()

    // MARK: Private state
    private var connection: Connection?
    private var spec: P7Spec?
    private var eventDispatcher: EventDispatcher!
    private var isRunning: Bool = false
    private var reconnectAttempts: Int = 0

    // Rate limiting
    private var lastResponseDate: Date = .distantPast

    // userID -> nick, per channel
    private var channelUsers: [UInt32: [UInt32: String]] = [:]

    // Spontaneous interjection — passive channel log
    private var channelMessageBuffer: [UInt32: [(nick: String, text: String)]] = [:]
    private var channelMessageCount: [UInt32: Int]  = [:]
    private var lastSpontaneousDate: [UInt32: Date] = [:]
    private let maxPassiveBufferSize = 20

    // Board thread context — injected into chat LLM calls so users can
    // discuss recently announced threads without an explicit mention.
    private struct BoardEntry {
        let nick: String; let subject: String; let text: String; let date: Date
    }
    private var boardContextByChannel: [UInt32: [BoardEntry]] = [:]

    // Tracks the last time the bot itself posted in each channel.
    // Used by respondAfterBotPost to keep the conversation open.
    private var lastBotPostByChannel: [UInt32: Date] = [:]
    private let applicationInfo = WiredApplicationInfo.current().overriding(name: "WiredChatBot")

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

        // P7 v1.3: accept any server identity fingerprint and log it.
        // A bot has no interactive UI for trust decisions, so we accept silently
        // and leave strict enforcement to human clients.
        conn.serverTrustHandler = { fingerprint, isNewKey, _ in
            if isNewKey {
                BotLogger.info("New server identity fingerprint: \(fingerprint)")
            } else {
                BotLogger.debug("Server identity fingerprint: \(fingerprint)")
            }
            return true
        }

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
        // Subscribe to board broadcasts so the server sends wired.board.post_added
        // and wired.board.thread_added to this connection.
        if let spec = self.spec {
            let sub = P7Message(withName: "wired.board.subscribe_boards", spec: spec)
            _ = connection.send(message: sub)
            BotLogger.info("Subscribed to board broadcasts")
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
            let wait = limit - elapsed
            BotLogger.debug("[\(chatID)] Rate-limited: waiting \(String(format: "%.1f", wait))s before sending")
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
                self?.sendChatNow(text, to: chatID)
            }
        } else {
            sendChatNow(text, to: chatID)
        }
    }

    private func sendChatNow(_ text: String, to chatID: UInt32) {
        guard let connection, let spec, connection.isConnected() else {
            BotLogger.warning("[\(chatID)] sendChatNow: not connected — message dropped")
            return
        }

        let maxLen   = config.behavior.maxResponseLength
        let truncated = text.count > maxLen
        let body     = truncated ? String(text.prefix(maxLen - 1)) + "…" : text
        if truncated {
            BotLogger.debug("[\(chatID)] Response truncated: \(text.count) → \(body.count) chars (maxResponseLength=\(maxLen))")
        }

        let msg = P7Message(withName: "wired.chat.send_say", spec: spec)
        msg.addParameter(field: "wired.chat.id", value: chatID)
        msg.addParameter(field: "wired.chat.say", value: body)
        _ = connection.send(message: msg)
        lastResponseDate = Date()
        lastBotPostByChannel[chatID] = Date()
        BotLogger.debug("[\(chatID)] Sent: \(body.prefix(80))\(body.count > 80 ? "…" : "")")
    }

    // MARK: - LLM dispatch

    /// Sends `input` to the LLM asynchronously and posts the reply to `chatID`.
    ///
    /// Context key scheme (stable, survives nick changes):
    ///   - Public channel: `"channel-<chatID>-<userID>"`
    ///   - Private DM:     `"private-<userID>"`
    public func dispatchLLM(input: String, nick: String, userID: UInt32,
                            chatID: UInt32, isPrivate: Bool, prependNick: Bool = true) {
        guard let llm = llmProvider else {
            BotLogger.warning("No LLM provider configured; ignoring message")
            return
        }

        let ctxKey   = isPrivate ? "private-\(userID)" : "channel-\(chatID)-\(userID)"
        let ctx      = contextManager.context(for: ctxKey)
        let userTurn = prependNick ? "\(nick): \(input)" : input
        let llmCfg   = config.llm
        let behCfg   = config.behavior

        BotLogger.debug("[\(ctxKey)] dispatchLLM → nick='\(nick)' userID=\(userID) isPrivate=\(isPrivate)")
        BotLogger.debug("[\(ctxKey)] Input: \(input.prefix(120))\(input.count > 120 ? "…" : "")")

        Task {
            do {
                // ── Step 1: Summarise oldest messages if the context window is full ──
                if llmCfg.enableSummarization,
                   let toSummarize = ctx.messagesForSummarization() {
                    BotLogger.debug("[\(ctxKey)] Summarisation: calling LLM to compress \(toSummarize.count) old messages…")
                    let excerpt = toSummarize
                        .map { "\($0.role): \($0.content)" }
                        .joined(separator: "\n")
                    let summaryPrompt = [LLMMessage(
                        role: "user",
                        content: "Summarise this conversation excerpt in 2-3 sentences, " +
                                 "keeping key facts and decisions:\n\n\(excerpt)"
                    )]
                    let t0 = Date()
                    let summary = try await llm.complete(messages: summaryPrompt, config: llmCfg)
                    let elapsed = Date().timeIntervalSince(t0)
                    ctx.applySummary(summary, replacing: toSummarize.count)
                    BotLogger.debug("[\(ctxKey)] Summarisation done in \(String(format: "%.2f", elapsed))s — preview: \(summary.prefix(80))")
                } else if !llmCfg.enableSummarization {
                    BotLogger.debug("[\(ctxKey)] Summarisation disabled (enableSummarization=false)")
                }

                // ── Step 2: Thread-timeout marker ──
                let threadTimeout = behCfg.threadTimeoutSeconds
                if ctx.isNewThread(timeoutSeconds: threadTimeout) {
                    ctx.add(role: "system", content: "--- New conversation after a break ---")
                    BotLogger.debug("[\(ctxKey)] Thread gap > \(Int(threadTimeout))s — separator injected")
                } else if threadTimeout > 0 {
                    BotLogger.debug("[\(ctxKey)] Thread still active (timeout=\(Int(threadTimeout))s)")
                }
                ctx.updateLastInteraction()

                // ── Step 3: Build system prompt + channel awareness layer ──
                let system    = self.buildSystemPrompt()
                let awareness = isPrivate ? nil : self.buildChannelAwareness(chatID: chatID,
                                                                             excludingText: input)
                if let aw = awareness {
                    let lineCount = aw.components(separatedBy: "\n").count - 1 // subtract header
                    BotLogger.debug("[\(ctxKey)] Channel awareness: \(lineCount) recent message(s) injected")
                } else {
                    BotLogger.debug("[\(ctxKey)] Channel awareness: none (private=\(isPrivate) or empty buffer)")
                }

                // ── Step 4: Build message array with temporal filtering ──
                let messages = ctx.buildMessages(
                    systemPrompt: system,
                    channelAwareness: awareness,
                    userInput: userTurn,
                    maxAgeSeconds: llmCfg.contextMaxAgeSeconds
                )

                // ── Step 5: Call LLM ──
                let provider = type(of: llm)
                BotLogger.debug("[\(ctxKey)] → LLM call (\(provider)) with \(messages.count) message(s)…")
                let t0    = Date()
                let reply = try await llm.complete(messages: messages, config: llmCfg)
                let elapsed = Date().timeIntervalSince(t0)

                BotLogger.debug(
                    "[\(ctxKey)] ← LLM replied in \(String(format: "%.2f", elapsed))s" +
                    " (\(reply.count) chars): \(reply.prefix(100))\(reply.count > 100 ? "…" : "")"
                )
                ctx.add(role: "user", content: userTurn)
                ctx.recordAssistantResponse(reply)
                await MainActor.run { self.sendChat(reply, to: chatID) }

            } catch {
                BotLogger.error("[\(ctxKey)] LLM error: \(error.localizedDescription)")
            }
        }
    }

    private func buildSystemPrompt() -> String {
        let id  = config.identity
        let llm = config.llm
        let beh = config.behavior
        let serverName = connection?.serverInfo?.serverName ?? ""

        // ── Identity preamble ──────────────────────────────────────────────────
        let preamble: String
        if let custom = id.identityPreamble, !custom.isEmpty {
            // User-defined preamble: substitute placeholders
            let vars: [String: String] = [
                "nick": id.nick, "model": llm.model, "provider": llm.provider,
                "status": id.status, "server": serverName
            ]
            preamble = vars.reduce(custom) { result, pair in
                result.replacingOccurrences(of: "{\(pair.key)}", with: pair.value)
            }
        } else {
            // Auto-generated preamble
            var lines: [String] = []
            lines.append("You are \(id.nick), an AI chatbot connected to a Wired chat server.")
            if !serverName.isEmpty { lines.append("Server: \(serverName)") }
            lines.append("Your nick: \(id.nick)")
            if !id.status.isEmpty { lines.append("Your status: \(id.status)") }
            lines.append("You are powered by \(llm.model) (\(llm.provider)).")
            lines.append("""
                Your capabilities:
                - Chat with users on public channels and in private messages
                - Monitor board threads and announce or summarise new posts
                - Respond to commands such as !ping, !help, !ask, !tldr
                - Maintain conversation context across multiple messages
                """)
            lines.append("""
                Self-awareness rules (always follow these):
                - You KNOW you are an AI bot. Never deny or be uncertain about your nature.
                - Always answer questions about yourself accurately (your name, purpose, model).
                - When asked how you feel, you may answer creatively but always acknowledge \
                you are an AI without human emotions.
                """)
            preamble = lines.joined(separator: "\n")
        }

        // ── User-defined system prompt (personality, tone, extra instructions) ──
        var parts = [preamble]
        if !llm.systemPrompt.isEmpty { parts.append(llm.systemPrompt) }
        // Chat context uses "nick: message" format so the LLM knows who is speaking.
        // Explicitly forbid it from echoing that format back in responses.
        parts.append("IMPORTANT: Never start your responses with a nick prefix like \"Name:\" or \"Name: \". Reply directly without any name prefix.")
        if beh.respondInUserLanguage {
            parts.append(
                "IMPORTANT: Always reply in the exact same language the user writes in. " +
                "Detect it from each message and never switch languages unless the user does."
            )
        }
        BotLogger.debug("[prompt] respondInUserLanguage=\(beh.respondInUserLanguage)")
        return parts.joined(separator: "\n")
    }

    /// Records a board thread or reply so the bot can discuss it in subsequent
    /// chat conversations. Call this for every board event that was announced.
    public func recordBoardActivity(nick: String, subject: String, text: String) {
        let entry = BoardEntry(nick: nick, subject: subject, text: text, date: Date())
        let maxAge = config.llm.contextMaxAgeSeconds > 0 ? config.llm.contextMaxAgeSeconds : 3600
        let cutoff = Date().addingTimeInterval(-maxAge)
        for chatID in config.server.channels {
            var entries = (boardContextByChannel[chatID] ?? [])
                .filter { $0.date > cutoff }
            entries.append(entry)
            boardContextByChannel[chatID] = entries
        }
    }

    /// Builds the recent channel log as a system-level awareness snippet.
    /// Excludes the triggering message itself to avoid duplication.
    private func buildChannelAwareness(chatID: UInt32, excludingText: String) -> String? {
        var parts: [String] = []

        // Recent chat messages
        if let buf = channelMessageBuffer[chatID], buf.count > 1 {
            let log = buf.dropLast()
                .suffix(10)
                .map { "[\($0.nick)] \($0.text)" }
                .joined(separator: "\n")
            parts.append("Recent channel activity (context only — do not repeat or summarise this):\n\(log)")
        }

        // Recent board threads — lets users ask follow-up questions about them
        let maxAge = config.llm.contextMaxAgeSeconds > 0 ? config.llm.contextMaxAgeSeconds : 3600
        let cutoff = Date().addingTimeInterval(-maxAge)
        if let entries = boardContextByChannel[chatID] {
            let recent = entries.filter { $0.date > cutoff }
            if !recent.isEmpty {
                let boardLog = recent.map { e -> String in
                    var line = "Thread by \(e.nick): \"\(e.subject)\""
                    if !e.text.isEmpty { line += "\nContent: \(e.text)" }
                    return line
                }.joined(separator: "\n---\n")
                parts.append("Recently announced board threads (user may ask follow-up questions about these):\n\(boardLog)")
            }
        }

        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
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

    // MARK: - Spontaneous interjection

    /// Passively records every visible message in a channel.
    /// Every `spontaneousCheckInterval` messages (and once the cooldown has elapsed),
    /// asks the LLM whether it wants to interject naturally into the conversation.
    public func trackMessage(nick: String, text: String, chatID: UInt32) {
        let cfg = config.behavior
        guard cfg.spontaneousReply else { return }

        // Accumulate in rolling buffer
        var buf = channelMessageBuffer[chatID] ?? []
        buf.append((nick: nick, text: text))
        if buf.count > maxPassiveBufferSize { buf.removeFirst() }
        channelMessageBuffer[chatID] = buf

        // Increment per-channel counter
        let count = (channelMessageCount[chatID] ?? 0) + 1
        channelMessageCount[chatID] = count
        BotLogger.debug("[\(chatID)] Passive buffer: \(buf.count)/\(maxPassiveBufferSize) msgs, counter=\(count)/\(cfg.spontaneousCheckInterval)")

        // Only check every N messages
        guard count % cfg.spontaneousCheckInterval == 0 else { return }

        // Respect per-channel cooldown
        let lastDate    = lastSpontaneousDate[chatID] ?? .distantPast
        let sinceLastS  = Date().timeIntervalSince(lastDate)
        let cooldown    = cfg.spontaneousCooldownSeconds
        guard sinceLastS >= cooldown else {
            BotLogger.debug("[\(chatID)] Spontaneous: cooldown active (\(String(format: "%.0f", sinceLastS))s / \(Int(cooldown))s)")
            return
        }

        BotLogger.debug("[\(chatID)] Spontaneous: check triggered (every \(cfg.spontaneousCheckInterval) msgs, cooldown OK)")
        checkSpontaneousInterjection(chatID: chatID, buffer: buf)
    }

    /// Sends the recent channel log to the LLM with a meta-prompt asking whether
    /// it should join the conversation. Expects "RESPOND: <msg>" or "SILENT".
    private func checkSpontaneousInterjection(chatID: UInt32,
                                              buffer: [(nick: String, text: String)]) {
        guard let llm = llmProvider else { return }

        let botNick = config.identity.nick
        let chatLog = buffer.map { "[\($0.nick)] \($0.text)" }.joined(separator: "\n")

        let metaPrompt = """
        You are \(botNick), observing a public chat. Read the recent messages below \
        and decide if you have something genuinely useful, interesting, or fun to contribute.

        Reply with exactly one of:
        - RESPOND: <your message>
        - SILENT

        Only interject if you can add real value. Stay quiet if the conversation \
        doesn't need you or if you have nothing meaningful to say.

        Recent chat:
        \(chatLog)
        """

        let messages = [LLMMessage(role: "user", content: metaPrompt)]

        Task {
            do {
                BotLogger.debug("[\(chatID)] Spontaneous: → LLM decision call (\(buffer.count) msgs in log)…")
                let t0    = Date()
                let reply = try await llm.complete(messages: messages, config: self.config.llm)
                let elapsed = Date().timeIntervalSince(t0)
                let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)

                BotLogger.debug("[\(chatID)] Spontaneous: ← LLM answered in \(String(format: "%.2f", elapsed))s — \(trimmed.prefix(60))")

                guard trimmed.uppercased().hasPrefix("RESPOND:") else {
                    BotLogger.debug("[\(chatID)] Spontaneous: SILENT — bot chose not to interject")
                    return
                }

                let text = String(trimmed.dropFirst("RESPOND:".count))
                    .trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty else {
                    BotLogger.debug("[\(chatID)] Spontaneous: RESPOND prefix found but message was empty — ignored")
                    return
                }

                BotLogger.debug("[\(chatID)] Spontaneous: RESPOND — interjecting: \(text.prefix(80))")
                await MainActor.run {
                    self.lastSpontaneousDate[chatID] = Date()
                    self.sendChat(text, to: chatID)
                }
                // Record so future context is aware of what the bot said
                let ctx = self.contextManager.context(for: "channel-\(chatID)")
                ctx.recordAssistantResponse(text)
            } catch {
                BotLogger.error("[\(chatID)] Spontaneous LLM check error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Filtering helpers

    /// Returns true if the bot posted in `chatID` within `threadTimeoutSeconds`.
    /// Used to keep a channel conversation open after a bot-initiated message.
    public func hasBotRecentlyPosted(in chatID: UInt32) -> Bool {
        guard let last = lastBotPostByChannel[chatID] else { return false }
        let timeout = config.behavior.threadTimeoutSeconds
        return timeout > 0 && Date().timeIntervalSince(last) < timeout
    }

    public func hasActiveConversation(userID: UInt32, chatID: UInt32) -> Bool {
        let key = "channel-\(chatID)-\(userID)"
        return contextManager.hasActiveConversation(for: key,
                                                    timeoutSeconds: config.behavior.threadTimeoutSeconds)
    }

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
    public func clientInfoApplicationName(for connection: Connection) -> String? { applicationInfo.name }
    public func clientInfoApplicationVersion(for connection: Connection) -> String? { applicationInfo.version }
    public func clientInfoApplicationBuild(for connection: Connection) -> String? { applicationInfo.build }
}
