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
        let isEncrypted = message.bool(forField: "wired.message.offline.encrypted") ?? false

        // Offline messages are always stored encrypted. The recipient must have registered
        // a public key (so the sender can encrypt), and the client must set is_encrypted=true.
        // Plaintext storage is never acceptable — it would let server admins read private messages.
        let recipientPublicKey: Data? = (try? App.databaseController.dbQueue.read { db in
            let row = try Row.fetchOne(db,
                sql: "SELECT offline_public_key FROM users WHERE username = ?",
                arguments: [recipientLogin])
            let keyData = row?["offline_public_key"] as? Data
            return (keyData != nil && !keyData!.isEmpty) ? keyData : nil
        }) ?? nil

        guard let _ = recipientPublicKey else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            Logger.warning("Rejected offline message for '\(recipientLogin)' — no public key registered (encryption required)")
            return
        }

        guard isEncrypted else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            Logger.warning("Rejected unencrypted offline message for '\(recipientLogin)' — is_encrypted must be true")
            return
        }

        var offlineMessage = OfflineMessage(
            senderLogin: senderLogin,
            recipientLogin: recipientLogin,
            body: body,
            sentAt: Date(),
            isEncrypted: isEncrypted
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

        struct PendingMessage {
            let id: Int64
            let senderLogin: String
            let senderNick: String?
            let body: String
            let sentAt: Date
            let isEncrypted: Bool
        }

        let messages: [PendingMessage]
        do {
            messages = try App.databaseController.dbQueue.read { db in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT om.id, om.sender_login, om.body, om.sent_at, om.is_encrypted,
                           u.last_nick AS sender_nick
                    FROM offline_messages om
                    LEFT JOIN users u ON u.username = om.sender_login
                    WHERE om.recipient_login = ?
                    ORDER BY om.sent_at ASC
                """, arguments: [recipientLogin])
                return rows.map {
                    let encryptedInt: Int = $0["is_encrypted"] ?? 0
                    return PendingMessage(
                        id: $0["id"],
                        senderLogin: $0["sender_login"],
                        senderNick: $0["sender_nick"],
                        body: $0["body"],
                        sentAt: $0["sent_at"],
                        isEncrypted: encryptedInt != 0
                    )
                }
            }
        } catch {
            Logger.error("Failed to load offline messages for '\(recipientLogin)': \(error)")
            return
        }

        guard !messages.isEmpty else { return }

        // Track which message IDs were successfully written to the socket.
        // Only those are deleted — if the connection drops mid-delivery the
        // remaining messages stay in the DB and will be re-delivered on next login.
        var deliveredIDs: [Int64] = []

        for msg in messages {
            let delivery = P7Message(withName: "wired.message.offline_message", spec: self.spec)
            delivery.addParameter(field: "wired.message.offline.sender_login", value: msg.senderLogin)
            delivery.addParameter(field: "wired.message.message", value: msg.body)
            delivery.addParameter(field: "wired.message.offline.date", value: msg.sentAt)
            if let nick = msg.senderNick, !nick.isEmpty {
                delivery.addParameter(field: "wired.message.offline.sender_nick", value: nick)
            }
            if msg.isEncrypted {
                delivery.addParameter(field: "wired.message.offline.encrypted", value: true)
            }
            if self.send(message: delivery, client: client) {
                deliveredIDs.append(msg.id)
            }
        }

        guard !deliveredIDs.isEmpty else { return }

        do {
            _ = try App.databaseController.dbQueue.write { db in
                try OfflineMessage
                    .filter(deliveredIDs.contains(Column("id")))
                    .deleteAll(db)
            }
        } catch {
            Logger.error("Failed to delete delivered offline messages for '\(recipientLogin)': \(error)")
        }

        Logger.info("Delivered \(deliveredIDs.count)/\(messages.count) offline message(s) to '\(recipientLogin)'")
    }

    func sendOfflineUserList(to client: Client) {
        let onlineLogins = Set(App.clientsController.allConnectedLogins())

        let entries: [(login: String, nick: String)]
        do {
            entries = try App.databaseController.dbQueue.read { db in
                // Only include users who have a last_nick set (i.e. connected at least once
                // since v15). This avoids exposing login names or account full names.
                let rows = try Row.fetchAll(db, sql: """
                    SELECT username, last_nick FROM users
                    WHERE username IS NOT NULL AND username != ''
                      AND last_login_at IS NOT NULL
                      AND last_login_at > unixepoch('now') - 2592000
                      AND last_nick IS NOT NULL AND last_nick != ''
                    ORDER BY last_nick ASC
                """)
                return rows.map { row in
                    (login: row["username"] as String, nick: row["last_nick"] as String)
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
