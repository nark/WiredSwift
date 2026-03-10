// WiredChatBot — BoardEventHandler.swift
// Handles wired.board.* events.

import Foundation
import WiredSwift

public final class BoardEventHandler {

    public func handleNewThread(message: P7Message, bot: BotController) {
        guard bot.config.behavior.announceNewThreads else { return }
        guard let subject = message.string(forField: "wired.board.subject") else { return }

        let nick  = message.string(forField: "wired.user.nick")  ?? "someone"
        let board = message.string(forField: "wired.board.board") ?? "Board"

        BotLogger.info("New thread '\(subject)' by \(nick) in \(board)")

        let announcement = bot.triggerEngine.format(
            bot.config.behavior.announceNewThreadMessage,
            with: ["nick": nick, "subject": subject, "board": board]
        )
        for chatID in bot.config.server.channels {
            bot.sendChat(announcement, to: chatID)
        }
    }

    public func handleNewPost(message: P7Message, bot: BotController) {
        let nick    = message.string(forField: "wired.user.nick")    ?? "someone"
        let subject = message.string(forField: "wired.board.subject") ?? ""
        let board   = message.string(forField: "wired.board.board")  ?? ""
        let text    = message.string(forField: "wired.board.text")   ?? ""
        let userID  = message.uint32(forField: "wired.user.id")      ?? 0

        BotLogger.info("New post by \(nick) in '\(subject)' [\(board)]")

        // Run board-post triggers
        guard let match = bot.triggerEngine.matchBoardPost(
            subject: subject, text: text, nick: nick, board: board)
        else { return }

        let vars: [String: String] = [
            "nick": nick, "subject": subject, "board": board, "text": text
        ]

        if match.trigger.useLLM {
            let prefix = match.trigger.llmPromptPrefix ?? ""
            let input  = prefix.isEmpty ? text : "\(prefix)\(text)"
            let chatID = bot.config.server.channels.first ?? 1
            BotLogger.debug("[board] Dispatching LLM for post by \(nick) in '\(subject)'")
            bot.dispatchLLM(input: input, nick: nick, userID: userID,
                            chatID: chatID, isPrivate: false)
        } else if let template = match.trigger.response {
            let announcement = bot.triggerEngine.format(template, with: vars)
            for chatID in bot.config.server.channels {
                bot.sendChat(announcement, to: chatID)
            }
        }
    }
}
