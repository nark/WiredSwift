// WiredChatBot — ChatEventHandler.swift
// Handles wired.chat.* messages.

import Foundation
import WiredSwift

public final class ChatEventHandler {

    public func handleSay(message: P7Message, bot: BotController) {
        guard
            let chatID = message.uint32(forField: "wired.chat.id"),
            let userID = message.uint32(forField: "wired.user.id"),
            let text   = message.string(forField: "wired.chat.say")
        else { return }

        let nick = bot.nick(ofUser: userID, in: chatID)
                ?? message.string(forField: "wired.user.nick")
                ?? "User\(userID)"

        guard !bot.shouldIgnore(nick: nick) else {
            BotLogger.debug("[\(chatID)] Ignored message from '\(nick)' (ignoredNicks or self)")
            return
        }

        BotLogger.debug("[\(chatID)] <\(nick)/\(userID)> \(text)")

        // Always feed the passive buffer (enables spontaneous interjection)
        bot.trackMessage(nick: nick, text: text, chatID: chatID)

        // 1. Check custom triggers first
        if let match = bot.triggerEngine.match(input: text, nick: nick,
                                               chatID: chatID, isPrivate: false) {
            let vars = ["nick": nick, "input": text, "chatID": "\(chatID)"]
            if match.trigger.useLLM {
                let prefix = match.trigger.llmPromptPrefix ?? ""
                BotLogger.debug("[\(chatID)] Trigger '\(match.trigger.pattern)' matched → LLM dispatch (prefix='\(prefix.prefix(30))')")
                bot.dispatchLLM(input: prefix + text, nick: nick, userID: userID,
                                chatID: chatID, isPrivate: false)
            } else if let tpl = match.trigger.response {
                BotLogger.debug("[\(chatID)] Trigger '\(match.trigger.pattern)' matched → static reply")
                bot.sendChat(bot.triggerEngine.format(tpl, with: vars), to: chatID)
            } else {
                BotLogger.debug("[\(chatID)] Trigger '\(match.trigger.pattern)' matched but has no action")
            }
            return
        }

        // 2. LLM response on mention / respondToAll
        let mentioned      = bot.isMentioned(in: text)
        let cfg            = bot.config.behavior
        let willRespond    = cfg.respondToAll || (cfg.respondToMentions && mentioned)

        BotLogger.debug(
            "[\(chatID)] Routing: mentioned=\(mentioned) respondToAll=\(cfg.respondToAll)" +
            " respondToMentions=\(cfg.respondToMentions) → \(willRespond ? "LLM dispatch" : "no response")"
        )

        if willRespond {
            bot.dispatchLLM(input: text, nick: nick, userID: userID,
                            chatID: chatID, isPrivate: false)
        }
    }

    public func handleMe(message: P7Message, bot: BotController) {
        guard
            let chatID = message.uint32(forField: "wired.chat.id"),
            let userID = message.uint32(forField: "wired.user.id"),
            let text   = message.string(forField: "wired.chat.me")
        else { return }

        let nick = bot.nick(ofUser: userID, in: chatID) ?? "User\(userID)"
        BotLogger.debug("[\(chatID)] * \(nick) \(text)")
    }

    public func handleTopic(message: P7Message, bot: BotController) {
        guard
            let chatID = message.uint32(forField: "wired.chat.id"),
            let topic  = message.string(forField: "wired.chat.topic")
        else { return }
        BotLogger.info("Channel \(chatID) topic: \(topic)")
    }
}
