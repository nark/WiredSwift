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
        guard bot.config.behavior.announceNewThreads else { return }

        let nick    = message.string(forField: "wired.user.nick")    ?? "someone"
        let subject = message.string(forField: "wired.board.subject") ?? ""
        BotLogger.info("New post by \(nick) in '\(subject)'")
    }
}
