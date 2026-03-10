// WiredChatBot — BoardEventHandler.swift
// Handles wired.board.* events.

import Foundation
import WiredSwift

public final class BoardEventHandler {

    public func handleNewThread(message: P7Message, bot: BotController) {
        guard let subject = message.string(forField: "wired.board.subject") else { return }

        let nick  = message.string(forField: "wired.user.nick")  ?? "someone"
        let board = message.string(forField: "wired.board.board") ?? "Board"

        BotLogger.info("New thread '\(subject)' by \(nick) in \(board)")

        guard let match = bot.triggerEngine.matchBoardEvent(
            eventType: "thread_added", subject: subject, text: "", nick: nick, board: board)
        else {
            BotLogger.debug("[board] thread_added: no matching trigger for '\(subject)'")
            return
        }

        if match.trigger.useLLM {
            let vars: [String: String] = ["nick": nick, "subject": subject, "board": board]
            let rawPrefix = match.trigger.llmPromptPrefix ?? ""
            let prefix    = rawPrefix.isEmpty ? "" : bot.triggerEngine.format(rawPrefix, with: vars)
            let input     = prefix.isEmpty ? subject : "\(prefix)\n\(subject)"
            let chatID    = bot.config.server.channels.first ?? 1
            BotLogger.debug("[board] Dispatching LLM for new thread '\(subject)' by \(nick)")
            bot.dispatchLLM(input: input, nick: nick, userID: 0,
                            chatID: chatID, isPrivate: false, prependNick: false)
        } else {
            fire(match: match, nick: nick, subject: subject, board: board, text: "", bot: bot)
        }
    }

    public func handleNewPost(message: P7Message, bot: BotController) {
        let nick    = message.string(forField: "wired.user.nick")    ?? "someone"
        let subject = message.string(forField: "wired.board.subject") ?? ""
        let board   = message.string(forField: "wired.board.board")  ?? ""
        let text    = message.string(forField: "wired.board.text")   ?? ""
        let userID  = message.uint32(forField: "wired.user.id")      ?? 0

        BotLogger.info("New reply by \(nick) in '\(subject)' [\(board)]")

        guard let match = bot.triggerEngine.matchBoardEvent(
            eventType: "thread_changed", subject: subject, text: text, nick: nick, board: board)
        else {
            BotLogger.debug("[board] thread_changed: no matching trigger for '\(subject)'")
            return
        }

        if match.trigger.useLLM {
            let vars: [String: String] = ["nick": nick, "subject": subject, "board": board, "text": text]
            let rawPrefix = match.trigger.llmPromptPrefix ?? ""
            let prefix    = rawPrefix.isEmpty ? "" : bot.triggerEngine.format(rawPrefix, with: vars)
            let input     = prefix.isEmpty ? text : "\(prefix)\n\(text)"
            let chatID    = bot.config.server.channels.first ?? 1
            BotLogger.debug("[board] Dispatching LLM for reply by \(nick) in '\(subject)'")
            bot.dispatchLLM(input: input, nick: nick, userID: userID,
                            chatID: chatID, isPrivate: false, prependNick: false)
        } else {
            fire(match: match, nick: nick, subject: subject, board: board, text: text, bot: bot)
        }
    }

    // MARK: - Private

    private func fire(match: BoardTriggerMatch, nick: String, subject: String,
                      board: String, text: String, bot: BotController) {
        guard let template = match.trigger.response else { return }
        let vars: [String: String] = [
            "nick": nick, "subject": subject, "board": board, "text": text
        ]
        let announcement = bot.triggerEngine.format(template, with: vars)
        for chatID in bot.config.server.channels {
            bot.sendChat(announcement, to: chatID)
        }
    }
}
