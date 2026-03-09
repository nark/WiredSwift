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
}

// MARK: - Identity

public struct IdentityConfig: Codable {
    public var nick:   String  = "WiredBot"
    public var status: String  = "Powered by AI"
    /// Base64-encoded icon data (same format Wired uses). nil = default icon.
    public var icon:   String? = nil
    /// Seconds before the bot sets itself as idle (0 = never)
    public var idleTimeout: Double = 0
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
}
