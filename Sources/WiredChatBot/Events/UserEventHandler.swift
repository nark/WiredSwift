// WiredChatBot — UserEventHandler.swift
// Handles wired.chat.user_* messages.

import Foundation
import WiredSwift

public final class UserEventHandler {

    public func handleUserList(message: P7Message, bot: BotController) {
        guard
            let chatID = message.uint32(forField: "wired.chat.id"),
            let userID = message.uint32(forField: "wired.user.id"),
            let nick   = message.string(forField: "wired.user.nick")
        else { return }
        bot.setNick(nick, forUser: userID, in: chatID)
    }

    public func handleUserJoin(message: P7Message, bot: BotController, connection: Connection) {
        guard
            let chatID = message.uint32(forField: "wired.chat.id"),
            let userID = message.uint32(forField: "wired.user.id"),
            let nick   = message.string(forField: "wired.user.nick")
        else { return }

        bot.setNick(nick, forUser: userID, in: chatID)

        // Don't greet ourselves
        guard nick != bot.config.identity.nick else { return }
        BotLogger.info("User '\(nick)' joined channel \(chatID)")

        if bot.config.behavior.greetOnJoin {
            let msg = bot.triggerEngine.format(
                bot.config.behavior.greetMessage,
                with: ["nick": nick, "chatID": "\(chatID)"]
            )
            bot.sendChat(msg, to: chatID)
        }
    }

    public func handleUserLeave(message: P7Message, bot: BotController, connection: Connection) {
        guard
            let chatID = message.uint32(forField: "wired.chat.id"),
            let userID = message.uint32(forField: "wired.user.id")
        else { return }

        let nick = bot.nick(ofUser: userID, in: chatID) ?? "User\(userID)"
        BotLogger.info("User '\(nick)' left channel \(chatID)")
        bot.removeUser(userID, from: chatID)

        if bot.config.behavior.farewellOnLeave && nick != bot.config.identity.nick {
            let msg = bot.triggerEngine.format(
                bot.config.behavior.farewellMessage,
                with: ["nick": nick, "chatID": "\(chatID)"]
            )
            bot.sendChat(msg, to: chatID)
        }
    }

    public func handleUserStatus(message: P7Message, bot: BotController) {
        guard
            let chatID = message.uint32(forField: "wired.chat.id"),
            let userID = message.uint32(forField: "wired.user.id"),
            let nick   = message.string(forField: "wired.user.nick")
        else { return }
        bot.setNick(nick, forUser: userID, in: chatID)
    }
}
