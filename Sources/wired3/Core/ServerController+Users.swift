//
//  ServerController+Users.swift
//  wired3
//
import Foundation
import WiredSwift

extension ServerController {
    private enum WiredUserState: UInt32 {
        case loggedIn = 2
        case transferring = 3
    }

    private func activeTransfer(for client: Client) -> Transfer? {
        if let transfer = client.transfer {
            return transfer
        }

        guard let username = client.user?.username else {
            return nil
        }

        return App.clientsController.connectedClientsSnapshot().first {
            $0.user?.username == username && $0.transfer != nil
        }?.transfer
    }

    func broadcastUserStatusForRelatedSessions(of client: Client) {
        guard let username = client.user?.username else {
            if client.state == .LOGGED_IN {
                sendUserStatus(forClient: client)
            }
            return
        }

        let relatedClients = App.clientsController.connectedClientsSnapshot().filter {
            $0.state == .LOGGED_IN && $0.user?.username == username
        }

        for relatedClient in relatedClients {
            sendUserStatus(forClient: relatedClient)
        }
    }

    private func addTransferStatus(to message: P7Message, for client: Client) {
        if let transfer = activeTransfer(for: client) {
            let snapshot = transfer.statusSnapshot()
            message.addParameter(field: "wired.user.state", value: WiredUserState.transferring.rawValue)
            message.addParameter(field: "wired.transfer.type", value: snapshot.type.rawValue)
            message.addParameter(field: "wired.file.path", value: snapshot.path)
            message.addParameter(field: "wired.transfer.data_size", value: snapshot.dataSize)
            message.addParameter(field: "wired.transfer.rsrc_size", value: snapshot.rsrcSize)
            message.addParameter(field: "wired.transfer.transferred", value: snapshot.transferred)
            message.addParameter(field: "wired.transfer.speed", value: snapshot.speed)
            message.addParameter(field: "wired.transfer.queue_position", value: UInt32(max(0, snapshot.queuePosition)))
        } else {
            message.addParameter(field: "wired.user.state", value: WiredUserState.loggedIn.rawValue)
        }
    }

    func receiveUserSetNick(_ client: Client, _ message: P7Message) {
        let previousNick = client.nick ?? ""
        if let nick = message.string(forField: "wired.user.nick") {
            client.nick = nick
        }

        let response = P7Message(withName: "wired.okay", spec: self.spec)

        App.serverController.reply(client: client, reply: response, message: message)

        // broadcast if already logged in
        if client.state == .LOGGED_IN && client.user != nil {
            let newNick = client.nick ?? ""
            if previousNick != newNick {
                self.recordEvent(.userChangedNick, client: client, parameters: [previousNick, newNick])
            }
            self.sendUserStatus(forClient: client)
        }
    }

    func receiveUserSetStatus(_ client: Client, _ message: P7Message) {
        if let status = message.string(forField: "wired.user.status") {
            client.status = status
        }

        let response = P7Message(withName: "wired.okay", spec: self.spec)
        _ = self.send(message: response, client: client)

        // broadcast if already logged in
        if client.state == .LOGGED_IN && client.user != nil {
            self.sendUserStatus(forClient: client)
        }
    }

    func receiveUserSetIcon(_ client: Client, _ message: P7Message) {
        if let icon = message.data(forField: "wired.user.icon") {
            client.icon = icon
        }

        let response = P7Message(withName: "wired.okay", spec: self.spec)
        _ = self.send(message: response, client: client)

        // broadcast if already logged in
        if client.state == .LOGGED_IN {
            self.sendUserStatus(forClient: client)
        }
    }

    func receiveUserSetIdle(_ client: Client, _ message: P7Message) {
        if let idle = message.bool(forField: "wired.user.idle") {
            client.idle = idle
        } else {
            client.idle = true
        }

        let response = P7Message(withName: "wired.okay", spec: self.spec)
        _ = self.send(message: response, client: client)

        // broadcast if already logged in
        if client.state == .LOGGED_IN {
            self.sendUserStatus(forClient: client)
        }
    }

    func receiveUserGetInfo(_ fromClient: Client, _ message: P7Message) {
        guard let user = fromClient.user else { return }
        if !user.hasPrivilege(name: "wired.account.user.get_info") {
            App.serverController.replyError(client: fromClient, error: "wired.error.permission_denied", message: message)

            return
        }

        guard let userID = message.uint32(forField: "wired.user.id") else { return }
        guard let client = App.clientsController.user(withID: userID) else { return }

        let response = P7Message(withName: "wired.user.info", spec: self.spec)

        response.addParameter(field: "wired.user.id", value: client.userID ?? "")
        response.addParameter(field: "wired.user.nick", value: client.nick ?? "")
        response.addParameter(field: "wired.user.status", value: client.status ?? "")
        response.addParameter(field: "wired.user.idle", value: client.idle)
        response.addParameter(field: "wired.user.icon", value: client.icon ?? "")
        addTransferStatus(to: response, for: client)

        response.addParameter(field: "wired.user.login", value: client.user?.username ?? "")
        response.addParameter(field: "wired.user.ip", value: client.socket.getClientIP() ?? "")
        response.addParameter(field: "wired.user.host", value: client.socket.getClientHostname() ?? "")
        response.addParameter(field: "wired.user.cipher.name", value: client.socket.cipherType.description)
        response.addParameter(field: "wired.user.cipher.bits", value: UInt32(client.socket.checksumLength(client.socket.digest.type)))

        if let loginTime = client.loginTime {
            response.addParameter(field: "wired.user.login_time", value: loginTime)
        }

        if let idleTime = client.idleTime {
            response.addParameter(field: "wired.user.idle_time", value: idleTime)
        }

        response.addParameter(field: "wired.info.application.name", value: client.applicationName)
        response.addParameter(field: "wired.info.application.version", value: client.applicationVersion)
        response.addParameter(field: "wired.info.application.build", value: client.applicationBuild)
        response.addParameter(field: "wired.info.os.name", value: client.osName)
        response.addParameter(field: "wired.info.os.version", value: client.osVersion)
        response.addParameter(field: "wired.info.arch", value: client.arch)
        response.addParameter(field: "wired.info.supports_rsrc", value: client.supportsRsrc)

        App.serverController.reply(client: fromClient,
                                   reply: response,
                                   message: message)
        self.recordEvent(.userGotInfo, client: fromClient, parameters: [client.nick ?? client.user?.username ?? ""])
    }

    func receiveUserDisconnectUser(client: Client, message: P7Message) {
        guard let (_, target, disconnectMessage) = self.validateModerationTarget(
            client: client,
            message: message,
            requiredPrivilege: "wired.account.user.disconnect_users"
        ) else {
            return
        }

        let chats = App.chatsController.chats(containingUserID: target.userID)

        for chat in chats {
            let broadcast = P7Message(withName: "wired.chat.user_disconnect", spec: client.socket.spec)
            broadcast.addParameter(field: "wired.chat.id", value: chat.chatID)
            broadcast.addParameter(field: "wired.user.disconnected_id", value: target.userID)
            broadcast.addParameter(field: "wired.user.disconnect_message", value: disconnectMessage)

            chat.withClients { chatClient in
                App.serverController.send(message: broadcast, client: chatClient)
            }
        }

        self.disconnectClient(client: target, broadcastLeaves: false)
        self.replyOK(client: client, message: message)
        self.recordEvent(.userDisconnectedUser, client: client, parameters: [target.nick ?? target.user?.username ?? ""])
    }

    func receiveUserBanUser(client: Client, message: P7Message) {
        guard let (_, target, disconnectMessage) = self.validateModerationTarget(
            client: client,
            message: message,
            requiredPrivilege: "wired.account.user.ban_users"
        ) else {
            return
        }

        let expirationDate = message.date(forField: "wired.banlist.expiration_date")
        let targetIP = target.socket.getClientIP()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !targetIP.isEmpty else {
            self.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        do {
            _ = try App.banListController.addBan(ipPattern: targetIP, expirationDate: expirationDate)
        } catch let error as BanListError {
            self.replyBanListError(client: client, message: message, error: error)
            return
        } catch {
            Logger.error("Failed to ban user \(target.userID) at IP \(targetIP): \(error)")
            self.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        let chats = App.chatsController.chats(containingUserID: target.userID)

        for chat in chats {
            let broadcast = P7Message(withName: "wired.chat.user_ban", spec: client.socket.spec)
            broadcast.addParameter(field: "wired.chat.id", value: chat.chatID)
            broadcast.addParameter(field: "wired.user.disconnected_id", value: target.userID)
            broadcast.addParameter(field: "wired.user.disconnect_message", value: disconnectMessage)

            chat.withClients { chatClient in
                App.serverController.send(message: broadcast, client: chatClient)
            }
        }

        self.disconnectClient(client: target, broadcastLeaves: false)
        self.replyOK(client: client, message: message)
        self.recordEvent(.userBannedUser, client: client, parameters: [target.nick ?? target.user?.username ?? ""])
    }

    func validateModerationTarget(
        client: Client,
        message: P7Message,
        requiredPrivilege: String
    ) -> (User, Client, String)? {
        guard let actor = client.user else {
            self.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return nil
        }

        guard actor.hasPrivilege(name: requiredPrivilege) else {
            self.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return nil
        }

        guard let targetUserID = message.uint32(forField: "wired.user.id"),
              let disconnectMessage = message.string(forField: "wired.user.disconnect_message") else {
            self.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return nil
        }

        guard let target = App.clientsController.user(withID: targetUserID) else {
            self.replyError(client: client, error: "wired.error.user_not_found", message: message)
            return nil
        }

        guard target.user?.hasPrivilege(name: "wired.account.user.cannot_be_disconnected") != true else {
            self.replyError(client: client, error: "wired.error.user_cannot_be_disconnected", message: message)
            return nil
        }

        return (actor, target, disconnectMessage)
    }

    func sendUserStatus(forClient client: Client) {
        for chat in App.chatsController.publicChats {
            let broadcast = P7Message(withName: "wired.chat.user_status", spec: self.spec)

            broadcast.addParameter(field: "wired.chat.id", value: chat.chatID)
            broadcast.addParameter(field: "wired.user.id", value: client.userID)
            broadcast.addParameter(field: "wired.user.idle", value: client.idle)
            broadcast.addParameter(field: "wired.user.nick", value: client.nick)
            broadcast.addParameter(field: "wired.user.status", value: client.status)
            broadcast.addParameter(field: "wired.user.icon", value: client.icon)
            broadcast.addParameter(field: "wired.account.color", value: client.accountColor)
            addTransferStatus(to: broadcast, for: client)
            if let idleTime = client.idleTime {
                broadcast.addParameter(field: "wired.user.idle_time", value: idleTime)
            }

            App.clientsController.broadcast(message: broadcast)
        }
    }
}
