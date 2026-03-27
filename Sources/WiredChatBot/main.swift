// WiredChatBot — main.swift
// CLI entry point using swift-argument-parser.
// Two subcommands: `run` (default) and `generate-config`.

import Foundation
import ArgumentParser
import WiredSwift

// MARK: - Root command

struct WiredChatBotCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "wiredbot",
        abstract: "AI-powered chatbot for the Wired 3 protocol",
        discussion: """
            Connects to a Wired server and responds to chat messages using a
            configurable LLM backend (Ollama, OpenAI-compatible, or Anthropic).
            """,
        subcommands: [RunCommand.self, GenerateConfigCommand.self],
        defaultSubcommand: RunCommand.self
    )
}

// MARK: - run

struct RunCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Start the chatbot daemon"
    )

    @Option(name: .shortAndLong, help: "Path to JSON configuration file")
    var config: String = "wiredbot.json"

    @Option(name: .shortAndLong, help: "Path to wired.xml protocol specification")
    var spec: String?

    @Flag(name: .shortAndLong,
          help: "Run in foreground (skip fork even if daemon.foreground = false)")
    var foreground: Bool = false

    @Flag(name: .long, help: "Enable DEBUG logging (overrides config log level)")
    var verbose: Bool = false

    mutating func run() throws {
        // 1. Load config
        let botConfig: BotConfig
        do {
            botConfig = try ConfigLoader.load(from: config)
        } catch {
            fputs("Error loading config '\(config)': \(error.localizedDescription)\n", stderr)
            throw ExitCode.failure
        }

        // 2. Configure logging (before daemonize so early messages are visible)
        let daemon = DaemonController(config: botConfig.daemon)
        daemon.configureLogging(verbose: verbose)

        // 3. Daemonize if needed
        let runForeground = foreground || botConfig.daemon.foreground
        if !runForeground {
            daemon.daemonize()
        }

        // 4. Write PID file
        daemon.writePIDFile()

        // 5. Locate wired.xml
        let specPath: String
        if let s = spec {
            specPath = s
        } else if let found = ConfigLoader.findSpecPath(hint: botConfig.server.specPath) {
            specPath = found
        } else {
            fputs("""
                Cannot find wired.xml.
                Specify its path with --spec <path> or set server.specPath in the config.\n
                """, stderr)
            daemon.removePIDFile()
            throw ExitCode.failure
        }

        // 6. Create bot
        let bot = BotController(config: botConfig)

        // 7. Signal handlers
        SignalHandler.onTerminate = {
            BotLogger.info("Shutting down…")
            bot.stop()
            daemon.removePIDFile()
            Foundation.exit(0)
        }
        SignalHandler.onReload = {
            BotLogger.info("Config reload requested (restart required for full effect)")
        }
        SignalHandler.setup()

        // 8. Banner
        BotLogger.info("WiredChatBot 1.0 starting")
        BotLogger.info("Config    : \(config)")
        BotLogger.info("Spec      : \(specPath)")
        BotLogger.info("Server    : \(botConfig.server.url)")
        BotLogger.info("Nick      : \(botConfig.identity.nick)")
        BotLogger.info("LLM       : \(botConfig.llm.provider) / \(botConfig.llm.model)")
        BotLogger.info("Channels  : \(botConfig.server.channels)")

        // 9. Start (blocks)
        do {
            try bot.start(specPath: specPath)
        } catch {
            BotLogger.fatal("Bot failed: \(error.localizedDescription)")
            daemon.removePIDFile()
            throw ExitCode.failure
        }
    }
}

// MARK: - generate-config

struct GenerateConfigCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "generate-config",
        abstract: "Write a default wiredbot.json to disk"
    )

    @Option(name: .shortAndLong, help: "Output file path")
    var output: String = "wiredbot.json"

    mutating func run() throws {
        do {
            try ConfigLoader.generateDefault(at: output)
            print("Default config written to: \(output)")
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            throw ExitCode.failure
        }
    }
}

// MARK: - Entry

WiredChatBotCommand.main()
