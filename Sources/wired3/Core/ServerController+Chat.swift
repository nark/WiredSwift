//
//  ServerController+Chat.swift
//  wired3
//
//  Handles direct messaging (wired.message.*) between users.
//  The wired.chat.* messages are fully delegated to ChatsController
//  and routed via handleMessage in ServerController.swift.
//

// swiftlint:disable file_length function_body_length cyclomatic_complexity
import Foundation
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

        guard let body = message.string(forField: "wired.message.message"),
              !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        let reply = P7Message(withName: "wired.message.message", spec: self.spec)
        reply.addParameter(field: "wired.user.id", value: client.userID)
        reply.addParameter(field: "wired.message.message", value: body)

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
}
