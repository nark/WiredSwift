//
//  ServerController+Auth.swift
//  wired3
//
import Foundation
import WiredSwift

extension ServerController {

    func receiveClientInfo(_ client: Client, _ message: P7Message) {
        client.state = .GAVE_CLIENT_INFO

        if let applicationName = message.string(forField: "wired.info.application.name") {
            client.applicationName = applicationName
        }

        if let applicationVersion = message.string(forField: "wired.info.application.version") {
            client.applicationVersion = applicationVersion
        }

        if let applicationBuild = message.string(forField: "wired.info.application.build") {
            client.applicationBuild = applicationBuild
        }

        if let osName = message.string(forField: "wired.info.os.name") {
            client.osName = osName
        }

        if let osVersion = message.string(forField: "wired.info.os.version") {
            client.osVersion = osVersion
        }

        if let arch = message.string(forField: "wired.info.arch") {
            client.arch = arch
        }

        if let supportsRsrc = message.bool(forField: "wired.info.supports_rsrc") {
            client.supportsRsrc = supportsRsrc
        }

        App.serverController.reply(client: client,
                                   reply: self.serverInfoMessage(),
                                   message: message)
    }

    func receiveSendLogin(_ client: Client, _ message: P7Message) -> Bool {
        let clientIP = client.socket.getClientIP() ?? "unknown"

        do {
            if let ban = try App.banListController.getBan(forIPAddress: clientIP) {
                let reply = P7Message(withName: "wired.banned", spec: message.spec)
                if let expirationDate = ban.expirationDate {
                    reply.addParameter(field: "wired.banlist.expiration_date", value: expirationDate)
                }
                App.serverController.reply(client: client, reply: reply, message: message)
                Logger.warning("Rejected login for banned IP '\(clientIP)'")
                return false
            }
        } catch {
            Logger.error("Failed to check banlist for IP '\(clientIP)': \(error)")
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return false
        }

        // FINDING_A_001: Check if IP is temporarily banned due to repeated failures
        loginAttemptsLock.lock()
        if let record = loginAttempts[clientIP], let bannedUntil = record.bannedUntil {
            if Date() < bannedUntil {
                loginAttemptsLock.unlock()
                let reply = P7Message(withName: "wired.error", spec: message.spec)
                reply.addParameter(field: "wired.error.string", value: "Too many login attempts")
                reply.addParameter(field: "wired.error", value: UInt32(4))
                App.serverController.reply(client: client, reply: reply, message: message)
                Logger.warning("Login rate-limited for IP '\(clientIP)'")
                return false
            }
        }
        loginAttemptsLock.unlock()

        guard let login = message.string(forField: "wired.user.login") else {
            return false
        }

        guard let password = message.string(forField: "wired.user.password") else {
            return false
        }

        guard let user = App.usersController.user(withUsername: login, password: password) else {
            // SECURITY (FINDING_A_014): Perform dummy SHA-256 to prevent username enumeration via timing
            _ = (UUID().uuidString + password).sha256()

            let reply = P7Message(withName: "wired.error", spec: message.spec)
            reply.addParameter(field: "wired.error.string", value: "Login failed")
            reply.addParameter(field: "wired.error", value: UInt32(4
            ))
            App.serverController.reply(client: client, reply: reply, message: message)

            Logger.warning("Login from \(clientIP) failed for '\(login)': Wrong password")

            // FINDING_A_001: Track failed attempt and apply ban if threshold reached
            loginAttemptsLock.lock()
            var record = loginAttempts[clientIP] ?? LoginAttemptRecord(failureCount: 0, bannedUntil: nil)
            record.failureCount += 1
            if record.failureCount >= maxLoginAttempts {
                record.bannedUntil = Date().addingTimeInterval(loginBanDuration)
                Logger.warning("IP '\(clientIP)' banned for \(Int(loginBanDuration))s after \(record.failureCount) failed login attempts")
            }
            loginAttempts[clientIP] = record
            loginAttemptsLock.unlock()

            self.recordEvent(.userLoginFailed, nick: client.nick, login: login, ip: clientIP)

            return false
        }

        // FINDING_A_001: Reset failure counter on successful login
        loginAttemptsLock.lock()
        loginAttempts.removeValue(forKey: clientIP)
        loginAttemptsLock.unlock()

        client.user     = user
        client.state    = .LOGGED_IN

        let response = P7Message(withName: "wired.login", spec: self.spec)
        response.addParameter(field: "wired.user.id", value: client.userID)
        App.serverController.reply(client: client, reply: response, message: message)

        client.loginTime = Date()

        let clientInfo = [client.applicationName, client.applicationVersion]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        Logger.info("Login from \(clientIP) as '\(login)' succeeded using \(clientInfo.isEmpty ? "unknown client" : clientInfo)")

        App.serverController.reply(client: client, reply: accountPrivilegesMessage(for: user), message: message)
        self.recordEvent(
            .userLoggedIn,
            client: client,
            parameters: [client.applicationName, client.osName],
            loginOverride: login
        )

        return true
    }
}
