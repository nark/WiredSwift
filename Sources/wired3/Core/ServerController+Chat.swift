//
//  ServerController+Chat.swift
//  wired3
//
//  Handles direct messaging (wired.message.*) between users.
//  The wired.chat.* messages are fully delegated to ChatsController
//  and routed via handleMessage in ServerController.swift.
//

import Foundation
import GRDB
import WiredSwift

extension ServerController {

    // MARK: - Direct messages

    func receiveMessageSendMessage(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        if !user.hasPrivilege(name: "wired.account.message.send_messages") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let recipientID = message.uint32(forField: "wired.user.id"),
              let recipient = App.clientsController.user(withID: recipientID) else {
            App.serverController.replyError(client: client, error: "wired.error.user_not_found", message: message)
            return
        }

        guard let body = message.string(forField: "wired.message.message") else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        let attachmentIDs = App.attachmentsController.attachmentIDsFromMessage(message) ?? []
        let hasText = !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasText || !attachmentIDs.isEmpty else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        let descriptors = App.attachmentsController.descriptorsForMessageAttachmentIDs(
            attachmentIDs,
            client: client,
            context: AttachmentMessageContext(
                chatID: nil,
                recipientID: recipientID,
                boardPath: nil,
                threadUUID: nil,
                postUUID: nil
            )
        )
        guard attachmentIDs.isEmpty || descriptors != nil else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        let reply = P7Message(withName: "wired.message.message", spec: self.spec)
        reply.addParameter(field: "wired.user.id", value: client.userID)
        reply.addParameter(field: "wired.message.message", value: body)
        if let descriptors, !descriptors.isEmpty {
            reply.addParameter(field: "wired.attachment.descriptors", value: App.attachmentsController.descriptorStrings(descriptors))
            App.attachmentsController.refreshEphemeralAttachmentLifetime(ids: attachmentIDs)
        }

        _ = self.send(message: reply, client: recipient)
        App.serverController.replyOK(client: client, message: message)
        self.recordEvent(.messageSent, client: client, parameters: [recipient.nick ?? recipient.user?.username ?? ""])
    }

    // MARK: - Broadcasts

    func receiveMessageSendBroadcast(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        if !user.hasPrivilege(name: "wired.account.message.broadcast") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let body = message.string(forField: "wired.message.broadcast"),
              !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        // SECURITY (FINDING_C_012): Rate limit broadcasts (max 5/min per user)
        let now = Date()
        let broadcastExceeded: Bool = {
            self.broadcastRateLock.lock()
            defer { self.broadcastRateLock.unlock() }
            var timestamps = self.broadcastTimestamps[client.userID] ?? []
            let cutoff = now.addingTimeInterval(-60.0)
            timestamps = timestamps.filter { $0 > cutoff }
            if timestamps.count >= Self.broadcastRateLimitPerMinute {
                return true
            }
            timestamps.append(now)
            self.broadcastTimestamps[client.userID] = timestamps
            return false
        }()
        if broadcastExceeded {
            Logger.warning("Broadcast rate limit exceeded for user \(client.userID)")
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        let broadcast = P7Message(withName: "wired.message.broadcast", spec: self.spec)
        broadcast.addParameter(field: "wired.user.id", value: client.userID)
        broadcast.addParameter(field: "wired.message.broadcast", value: body)

        App.clientsController.broadcast(message: broadcast)
        App.serverController.replyOK(client: client, message: message)
        self.recordEvent(.messageBroadcasted, client: client)
    }

    // MARK: - Offline messages

    func receiveMessageSendOfflineMessage(client: Client, message: P7Message) {
        guard let senderUser = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard senderUser.hasPrivilege(name: "wired.account.message.send_offline_messages") else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let recipientLogin = message.string(forField: "wired.message.offline.recipient_login"),
              !recipientLogin.isEmpty else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let body = message.string(forField: "wired.message.message"),
              !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        // Verify the recipient account exists
        guard App.usersController.userExists(withUsername: recipientLogin) else {
            App.serverController.replyError(client: client, error: "wired.error.user_not_found", message: message)
            return
        }

        // If the recipient is currently online, deliver immediately instead
        if let onlineClient = App.clientsController.user(withLogin: recipientLogin) {
            let reply = P7Message(withName: "wired.message.message", spec: self.spec)
            reply.addParameter(field: "wired.user.id", value: client.userID)
            reply.addParameter(field: "wired.message.message", value: body)
            _ = self.send(message: reply, client: onlineClient)
            App.serverController.replyOK(client: client, message: message)
            return
        }

        let senderLogin = senderUser.username ?? ""
        var offlineMessage = OfflineMessage(
            senderLogin: senderLogin,
            recipientLogin: recipientLogin,
            body: body,
            sentAt: Date()
        )

        do {
            try App.databaseController.dbQueue.write { db in
                try offlineMessage.insert(db)
            }
        } catch {
            Logger.error("Failed to store offline message for '\(recipientLogin)': \(error)")
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        App.serverController.replyOK(client: client, message: message)
        Logger.info("Offline message from '\(senderLogin)' stored for '\(recipientLogin)'")
    }

    func deliverOfflineMessages(to client: Client) {
        guard let recipientLogin = client.user?.username else { return }

        let messages: [OfflineMessage]
        do {
            messages = try App.databaseController.dbQueue.read { db in
                try OfflineMessage
                    .filter(Column("recipient_login") == recipientLogin)
                    .order(Column("sent_at").asc)
                    .fetchAll(db)
            }
        } catch {
            Logger.error("Failed to load offline messages for '\(recipientLogin)': \(error)")
            return
        }

        guard !messages.isEmpty else { return }

        for msg in messages {
            let delivery = P7Message(withName: "wired.message.offline_message", spec: self.spec)
            delivery.addParameter(field: "wired.message.offline.sender_login", value: msg.senderLogin)
            delivery.addParameter(field: "wired.message.message", value: msg.body)
            delivery.addParameter(field: "wired.message.offline.date", value: msg.sentAt)
            _ = self.send(message: delivery, client: client)
        }

        do {
            try App.databaseController.dbQueue.write { db in
                try OfflineMessage
                    .filter(Column("recipient_login") == recipientLogin)
                    .deleteAll(db)
            }
        } catch {
            Logger.error("Failed to delete delivered offline messages for '\(recipientLogin)': \(error)")
        }

        Logger.info("Delivered \(messages.count) offline message(s) to '\(recipientLogin)'")
    }

    func sendOfflineUserList(to client: Client) {
        let onlineLogins = Set(App.clientsController.allConnectedLogins())

        let entries: [(login: String, nick: String)]
        do {
            entries = try App.databaseController.dbQueue.read { db in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT username, last_nick, full_name FROM users
                    WHERE username IS NOT NULL AND username != ''
                      AND (last_login_at IS NULL OR last_login_at > unixepoch('now') - 2592000)
                    ORDER BY username ASC
                """)
                return rows.map { row in
                    let login: String = row["username"]
                    let lastNick: String? = row["last_nick"]
                    let fullName: String? = row["full_name"]
                    let nick = lastNick.flatMap { $0.isEmpty ? nil : $0 }
                           ?? fullName.flatMap { $0.isEmpty ? nil : $0 }
                           ?? login
                    return (login: login, nick: nick)
                }
            }
        } catch {
            Logger.error("Failed to load offline user list: \(error)")
            return
        }

        for entry in entries where !onlineLogins.contains(entry.login) {
            let msg = P7Message(withName: "wired.user.offline_list", spec: self.spec)
            msg.addParameter(field: "wired.user.login", value: entry.login)
            msg.addParameter(field: "wired.user.nick", value: entry.nick)
            _ = self.send(message: msg, client: client)
        }

        let done = P7Message(withName: "wired.user.offline_list.done", spec: self.spec)
        _ = self.send(message: done, client: client)
    }
}
