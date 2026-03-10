// WiredChatBot — BotConfig.swift
// Codable configuration models for the Wired chatbot daemon.

import Foundation

// MARK: - Root

public struct BotConfig: Codable {
    public var server:   ServerConfig
    public var identity: IdentityConfig
    public var llm:      LLMConfig
    public var behavior: BehaviorConfig
    public var triggers: [TriggerConfig]
    public var daemon:   DaemonConfig

    public init() {
        server   = ServerConfig()
        identity = IdentityConfig()
        llm      = LLMConfig()
        behavior = BehaviorConfig()
        triggers = TriggerConfig.defaults
        daemon   = DaemonConfig()
    }
}

// MARK: - Server

public struct ServerConfig: Codable {
    /// Full Wired URL, e.g. "wired://bot:password@localhost:4871"
    public var url: String = "wired://guest@localhost:4871"
    /// Chat channel IDs to join after login (1 = public chat)
    public var channels: [UInt32] = [1]
    /// Seconds to wait before reconnecting
    public var reconnectDelay: Double = 30.0
    /// 0 = unlimited reconnect attempts
    public var maxReconnectAttempts: Int = 0
    /// Path to wired.xml protocol spec (nil = auto-detect)
    public var specPath: String? = nil

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url                 = try c.decodeIfPresent(String.self,   forKey: .url)                 ?? "wired://guest@localhost:4871"
        channels            = try c.decodeIfPresent([UInt32].self, forKey: .channels)            ?? [1]
        reconnectDelay      = try c.decodeIfPresent(Double.self,   forKey: .reconnectDelay)      ?? 30.0
        maxReconnectAttempts = try c.decodeIfPresent(Int.self,     forKey: .maxReconnectAttempts) ?? 0
        specPath            = try c.decodeIfPresent(String.self,   forKey: .specPath)
    }
}

// MARK: - Identity

public struct IdentityConfig: Codable {
    public var nick:   String  = "WiredBot"
    public var status: String  = "Powered by AI"
    /// Base64-encoded icon data (same format Wired uses). nil = default icon.
    public var icon:   String? = nil
    /// Seconds before the bot sets itself as idle (0 = never)
    public var idleTimeout: Double = 0

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nick        = try c.decodeIfPresent(String.self, forKey: .nick)        ?? "WiredBot"
        status      = try c.decodeIfPresent(String.self, forKey: .status)      ?? "Powered by AI"
        icon        = try c.decodeIfPresent(String.self, forKey: .icon)
        idleTimeout = try c.decodeIfPresent(Double.self, forKey: .idleTimeout) ?? 0
    }
}

// MARK: - LLM

public struct LLMConfig: Codable {
    /// "ollama" | "openai" | "anthropic"
    public var provider:      String  = "ollama"
    /// Base URL for the API (Ollama: http://localhost:11434, OpenAI: https://api.openai.com)
    public var endpoint:      String  = "http://localhost:11434"
    /// API key (required for openai / anthropic, optional for Ollama)
    public var apiKey:        String? = nil
    /// Model name, e.g. "llama3", "gpt-4o", "claude-sonnet-4-6"
    public var model:         String  = "llama3"
    /// System prompt injected at the start of every conversation
    public var systemPrompt:  String  = "You are WiredBot, a helpful and friendly AI chatbot on a Wired server. Be concise and keep responses under 300 characters when possible."
    public var temperature:   Double  = 0.7
    public var maxTokens:     Int     = 512
    /// Number of previous messages to keep per conversation context
    public var contextMessages: Int   = 10
    /// HTTP request timeout in seconds
    public var timeoutSeconds: Double = 30.0
    /// Messages older than this (seconds) are excluded from context. 0 = no expiry.
    public var contextMaxAgeSeconds: Double = 7200.0
    /// When true, the oldest half of the context is summarised via LLM instead of
    /// being silently dropped. Requires an extra LLM call when the context is full.
    public var enableSummarization: Bool = false

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        provider             = try c.decodeIfPresent(String.self,  forKey: .provider)             ?? "ollama"
        endpoint             = try c.decodeIfPresent(String.self,  forKey: .endpoint)             ?? "http://localhost:11434"
        apiKey               = try c.decodeIfPresent(String.self,  forKey: .apiKey)
        model                = try c.decodeIfPresent(String.self,  forKey: .model)                ?? "llama3"
        systemPrompt         = try c.decodeIfPresent(String.self,  forKey: .systemPrompt)         ?? "You are WiredBot, a helpful and friendly AI chatbot on a Wired server. Be concise and keep responses under 300 characters when possible."
        temperature          = try c.decodeIfPresent(Double.self,  forKey: .temperature)          ?? 0.7
        maxTokens            = try c.decodeIfPresent(Int.self,     forKey: .maxTokens)            ?? 512
        contextMessages      = try c.decodeIfPresent(Int.self,     forKey: .contextMessages)      ?? 10
        timeoutSeconds       = try c.decodeIfPresent(Double.self,  forKey: .timeoutSeconds)       ?? 30.0
        contextMaxAgeSeconds = try c.decodeIfPresent(Double.self,  forKey: .contextMaxAgeSeconds) ?? 7200.0
        enableSummarization  = try c.decodeIfPresent(Bool.self,    forKey: .enableSummarization)  ?? false
    }
}

// MARK: - Behavior

public struct BehaviorConfig: Codable {
    /// Respond when the bot's nick (or mentionKeywords) appears in a message
    public var respondToMentions:        Bool     = true
    /// Respond to every public message (ignores mention check)
    public var respondToAll:             Bool     = false
    /// Respond to private messages
    public var respondToPrivateMessages: Bool     = true

    public var greetOnJoin:     Bool   = true
    public var greetMessage:    String = "Welcome, {nick}!"
    public var farewellOnLeave: Bool   = false
    public var farewellMessage: String = "Goodbye, {nick}!"

    public var announceNewThreads:        Bool   = true
    public var announceNewThreadMessage:  String = "New board post: \"{subject}\" by {nick}"
    public var announceFileUploads:       Bool   = false
    public var announceFileMessage:       String = "{nick} uploaded: {filename}"

    /// Minimum seconds between bot responses (rate limiting)
    public var rateLimitSeconds:  Double = 2.0
    /// Truncate responses longer than this (in characters)
    public var maxResponseLength: Int    = 500
    /// Ignore messages sent by the bot itself
    public var ignoreOwnMessages: Bool   = true
    /// Nicks that will never receive a bot response
    public var ignoredNicks:      [String] = []
    /// Additional words/phrases treated as a mention of the bot
    public var mentionKeywords:   [String] = []

    // MARK: Thread detection
    /// Seconds of silence after which the bot considers a new conversation has
    /// started and injects a separator marker into the context. 0 = disabled.
    public var threadTimeoutSeconds: Double = 300.0

    // MARK: Language
    /// When true, the bot detects the language of each user message and always
    /// replies in the same language. The instruction is injected into the system
    /// prompt so the LLM handles detection natively.
    public var respondInUserLanguage: Bool = true

    // MARK: Spontaneous interjection
    /// Allow the bot to join conversations without being explicitly mentioned.
    /// The LLM decides whether to respond by replying "RESPOND: <msg>" or "SILENT".
    public var spontaneousReply: Bool = false
    /// Check for an interjection opportunity every N messages per channel.
    public var spontaneousCheckInterval: Int = 5
    /// Minimum seconds between two spontaneous replies in the same channel.
    public var spontaneousCooldownSeconds: Double = 120.0

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        respondToMentions        = try c.decodeIfPresent(Bool.self,     forKey: .respondToMentions)        ?? true
        respondToAll             = try c.decodeIfPresent(Bool.self,     forKey: .respondToAll)             ?? false
        respondToPrivateMessages = try c.decodeIfPresent(Bool.self,     forKey: .respondToPrivateMessages) ?? true
        greetOnJoin              = try c.decodeIfPresent(Bool.self,     forKey: .greetOnJoin)              ?? true
        greetMessage             = try c.decodeIfPresent(String.self,   forKey: .greetMessage)             ?? "Welcome, {nick}!"
        farewellOnLeave          = try c.decodeIfPresent(Bool.self,     forKey: .farewellOnLeave)          ?? false
        farewellMessage          = try c.decodeIfPresent(String.self,   forKey: .farewellMessage)          ?? "Goodbye, {nick}!"
        announceNewThreads       = try c.decodeIfPresent(Bool.self,     forKey: .announceNewThreads)       ?? true
        announceNewThreadMessage = try c.decodeIfPresent(String.self,   forKey: .announceNewThreadMessage) ?? "New board post: \"{subject}\" by {nick}"
        announceFileUploads      = try c.decodeIfPresent(Bool.self,     forKey: .announceFileUploads)      ?? false
        announceFileMessage      = try c.decodeIfPresent(String.self,   forKey: .announceFileMessage)      ?? "{nick} uploaded: {filename}"
        rateLimitSeconds         = try c.decodeIfPresent(Double.self,   forKey: .rateLimitSeconds)         ?? 2.0
        maxResponseLength        = try c.decodeIfPresent(Int.self,      forKey: .maxResponseLength)        ?? 500
        ignoreOwnMessages        = try c.decodeIfPresent(Bool.self,     forKey: .ignoreOwnMessages)        ?? true
        ignoredNicks             = try c.decodeIfPresent([String].self, forKey: .ignoredNicks)             ?? []
        mentionKeywords          = try c.decodeIfPresent([String].self, forKey: .mentionKeywords)          ?? []
        threadTimeoutSeconds     = try c.decodeIfPresent(Double.self,   forKey: .threadTimeoutSeconds)     ?? 300.0
        respondInUserLanguage    = try c.decodeIfPresent(Bool.self,     forKey: .respondInUserLanguage)    ?? true
        spontaneousReply         = try c.decodeIfPresent(Bool.self,     forKey: .spontaneousReply)         ?? false
        spontaneousCheckInterval = try c.decodeIfPresent(Int.self,      forKey: .spontaneousCheckInterval) ?? 5
        spontaneousCooldownSeconds = try c.decodeIfPresent(Double.self, forKey: .spontaneousCooldownSeconds) ?? 120.0
    }
}

// MARK: - Trigger

public struct TriggerConfig: Codable {
    /// Unique name for this trigger (used in logs / cooldowns)
    public var name:            String
    /// Regular expression matched against the full message text
    public var pattern:         String
    /// Which event types activate this trigger: "chat", "private", "all"
    public var eventTypes:      [String]   = ["chat", "private"]
    /// Static response template. Supports: {nick}, {input}, {chatID}
    public var response:        String?    = nil
    /// When true the input is forwarded to the LLM instead of using `response`
    public var useLLM:          Bool       = false
    /// Optional prefix prepended to the user's input before sending to LLM
    public var llmPromptPrefix: String?    = nil
    public var caseSensitive:   Bool       = false
    /// Per-user cooldown in seconds (0 = no cooldown)
    public var cooldownSeconds: Double     = 0

    // Default triggers bundled with a fresh config
    public static var defaults: [TriggerConfig] = [
        TriggerConfig(name: "ping",    pattern: "^!ping$",   eventTypes: ["chat","private"],
                      response: "Pong!", useLLM: false, cooldownSeconds: 0),
        TriggerConfig(name: "help",    pattern: "^!help",    eventTypes: ["chat","private"],
                      response: "Commands: !ping, !help, !ask <question> | Mention me for AI chat!",
                      useLLM: false, cooldownSeconds: 5),
        TriggerConfig(name: "ask",     pattern: "^!ask (.+)", eventTypes: ["chat","private"],
                      useLLM: true, cooldownSeconds: 2),
        TriggerConfig(name: "tldr",    pattern: "^!tldr (.+)", eventTypes: ["chat"],
                      useLLM: true, llmPromptPrefix: "Summarize this in one sentence: ",
                      cooldownSeconds: 5),
    ]

    // Memberwise init for static defaults
    init(name: String, pattern: String, eventTypes: [String] = ["chat","private"],
         response: String? = nil, useLLM: Bool = false, llmPromptPrefix: String? = nil,
         caseSensitive: Bool = false, cooldownSeconds: Double = 0) {
        self.name            = name
        self.pattern         = pattern
        self.eventTypes      = eventTypes
        self.response        = response
        self.useLLM          = useLLM
        self.llmPromptPrefix = llmPromptPrefix
        self.caseSensitive   = caseSensitive
        self.cooldownSeconds = cooldownSeconds
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Required fields — fail fast if absent
        name    = try c.decode(String.self, forKey: .name)
        pattern = try c.decode(String.self, forKey: .pattern)
        // Optional / defaulted fields
        eventTypes      = try c.decodeIfPresent([String].self, forKey: .eventTypes)      ?? ["chat", "private"]
        response        = try c.decodeIfPresent(String.self,   forKey: .response)
        useLLM          = try c.decodeIfPresent(Bool.self,     forKey: .useLLM)          ?? false
        llmPromptPrefix = try c.decodeIfPresent(String.self,   forKey: .llmPromptPrefix)
        caseSensitive   = try c.decodeIfPresent(Bool.self,     forKey: .caseSensitive)   ?? false
        cooldownSeconds = try c.decodeIfPresent(Double.self,   forKey: .cooldownSeconds) ?? 0
    }
}

// MARK: - Daemon

public struct DaemonConfig: Codable {
    /// Run in foreground (skip fork). Useful for debugging or Docker.
    public var foreground: Bool   = false
    public var pidFile:    String = "/tmp/wiredbot.pid"
    /// nil = log to stdout only
    public var logFile:    String? = nil
    /// VERBOSE | DEBUG | INFO | WARNING | ERROR
    public var logLevel:   String = "INFO"

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        foreground = try c.decodeIfPresent(Bool.self,   forKey: .foreground) ?? false
        pidFile    = try c.decodeIfPresent(String.self, forKey: .pidFile)    ?? "/tmp/wiredbot.pid"
        logFile    = try c.decodeIfPresent(String.self, forKey: .logFile)
        logLevel   = try c.decodeIfPresent(String.self, forKey: .logLevel)   ?? "INFO"
    }
}
