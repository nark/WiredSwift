// WiredChatBot — FileEventHandler.swift
// Handles file upload events.

import Foundation
import WiredSwift

public final class FileEventHandler {

    public func handleUpload(message: P7Message, bot: BotController) {
        guard bot.config.behavior.announceFileUploads else { return }

        let path     = message.string(forField: "wired.file.path") ?? "unknown"
        let nick     = message.string(forField: "wired.user.nick") ?? "someone"
        let filename = (path as NSString).lastPathComponent

        BotLogger.info("File upload: \(filename) by \(nick)")

        let announcement = bot.triggerEngine.format(
            bot.config.behavior.announceFileMessage,
            with: ["nick": nick, "filename": filename, "path": path]
        )
        for chatID in bot.config.server.channels {
            bot.sendChat(announcement, to: chatID)
        }
    }
}
