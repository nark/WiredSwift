// WiredChatBot — EventDispatcher.swift
// Implements ConnectionDelegate and routes incoming P7Messages to the
// appropriate specialised handler in BotController.

import Foundation
import WiredSwift

public final class EventDispatcher: NSObject, ConnectionDelegate {
    private weak var bot: BotController?

    public init(bot: BotController) {
        self.bot = bot
    }

    // MARK: - ConnectionDelegate

    public func connectionDidConnect(connection: Connection) {
        BotLogger.info("Connected to \(connection.URI)")
    }

    public func connectionDidFailToConnect(connection: Connection, error: Error) {
        BotLogger.error("Failed to connect: \(error.localizedDescription)")
        bot?.handleDisconnect(error: error)
    }

    public func connectionDisconnected(connection: Connection, error: Error?) {
        if let e = error { BotLogger.warning("Disconnected: \(e.localizedDescription)") }
        else              { BotLogger.info("Disconnected") }
        bot?.handleDisconnect(error: error)
    }

    public func connectionDidLogin(connection: Connection, message: P7Message) {
        bot?.handleLogin(connection: connection)
    }

    public func connectionDidReceivePriviledges(connection: Connection, message: P7Message) {
        BotLogger.debug("Privileges received")
    }

    public func connectionDidSendMessage(connection: Connection, message: P7Message) {
        // no-op
    }

    public func connectionDidReceiveMessage(connection: Connection, message: P7Message) {
        guard let bot = bot else { return }
        route(message: message, connection: connection, bot: bot)
    }

    public func connectionDidReceiveError(connection: Connection, message: P7Message) {
        BotLogger.warning("Server error: \(message.description)")
    }

    // MARK: - Routing

    private func route(message: P7Message, connection: Connection, bot: BotController) {
        switch message.name {

        // Chat
        case "wired.chat.say":
            bot.chatHandler.handleSay(message: message, bot: bot)
        case "wired.chat.me":
            bot.chatHandler.handleMe(message: message, bot: bot)
        case "wired.chat.topic":
            bot.chatHandler.handleTopic(message: message, bot: bot)

        // Users
        case "wired.chat.user_list":
            bot.userHandler.handleUserList(message: message, bot: bot)
        case "wired.chat.user_join":
            bot.userHandler.handleUserJoin(message: message, bot: bot, connection: connection)
        case "wired.chat.user_leave":
            bot.userHandler.handleUserLeave(message: message, bot: bot, connection: connection)
        case "wired.chat.user_status", "wired.chat.user_icon":
            bot.userHandler.handleUserStatus(message: message, bot: bot)

        // Boards
        case "wired.board.thread_added":
            bot.boardHandler.handleNewThread(message: message, bot: bot)
        case "wired.board.post_added":
            bot.boardHandler.handleNewPost(message: message, bot: bot)

        // Transfers / files
        case "wired.transfer.upload_file", "wired.transfer.upload":
            bot.fileHandler.handleUpload(message: message, bot: bot)

        default:
            break
        }
    }
}
