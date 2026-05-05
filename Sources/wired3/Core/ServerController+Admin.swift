//
//  ServerController+Admin.swift
//  wired3
//
//  Handles all administration messages:
//    - wired.banlist.*    — IP ban management
//    - wired.event.*     — audit-log browsing and subscription
//    - wired.settings.*  — server settings get/set
//    - wired.account.*   — user and group account CRUD
//
//  Also contains the event recording/broadcasting helpers used
//  by every other domain (Auth, Users, Chat, Boards, Files).
//

// swiftlint:disable file_length function_body_length cyclomatic_complexity
import Foundation
import WiredSwift

extension ServerController {

    // MARK: - Ban list

    func receiveBanListGetBans(client: Client, message: P7Message) {
        guard let user = client.user else {
            self.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard user.hasPrivilege(name: "wired.account.banlist.get_bans") else {
            self.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        do {
            let bans = try App.banListController.listBans()

            for ban in bans {
                let reply = P7Message(withName: "wired.banlist.list", spec: client.socket.spec)
                reply.addParameter(field: "wired.banlist.ip", value: ban.ipPattern)
                if let expirationDate = ban.expirationDate {
                    reply.addParameter(field: "wired.banlist.expiration_date", value: expirationDate)
                }
                self.reply(client: client, reply: reply, message: message)
            }

            let done = P7Message(withName: "wired.banlist.list.done", spec: client.socket.spec)
            self.reply(client: client, reply: done, message: message)
            self.recordEvent(.banlistGotBans, client: client)
        } catch {
            Logger.error("Failed to list bans: \(error)")
            self.replyError(client: client, error: "wired.error.internal_error", message: message)
        }
    }

    func receiveBanListAddBan(client: Client, message: P7Message) {
        guard let user = client.user else {
            self.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard user.hasPrivilege(name: "wired.account.banlist.add_bans") else {
            self.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let ipPattern = message.string(forField: "wired.banlist.ip") else {
            self.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        let expirationDate = message.date(forField: "wired.banlist.expiration_date")

        do {
            _ = try App.banListController.addBan(ipPattern: ipPattern, expirationDate: expirationDate)
            self.replyOK(client: client, message: message)
            self.recordEvent(.banlistAddedBan, client: client, parameters: [ipPattern])
        } catch let error as BanListError {
            self.replyBanListError(client: client, message: message, error: error)
        } catch {
            Logger.error("Failed to add ban '\(ipPattern)': \(error)")
            self.replyError(client: client, error: "wired.error.internal_error", message: message)
        }
    }

    func receiveBanListDeleteBans(client: Client, message: P7Message) {
        self.receiveBanListDeleteBan(client: client, message: message)
    }

    func receiveBanListDeleteBan(client: Client, message: P7Message) {
        guard let user = client.user else {
            self.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard user.hasPrivilege(name: "wired.account.banlist.delete_bans") else {
            self.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let ipPattern = message.string(forField: "wired.banlist.ip") else {
            self.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        let expirationDate = message.date(forField: "wired.banlist.expiration_date")

        do {
            try App.banListController.deleteBan(ipPattern: ipPattern, expirationDate: expirationDate)
            self.replyOK(client: client, message: message)
            self.recordEvent(.banlistDeletedBan, client: client, parameters: [ipPattern])
        } catch let error as BanListError {
            self.replyBanListError(client: client, message: message, error: error)
        } catch {
            Logger.error("Failed to delete ban '\(ipPattern)': \(error)")
            self.replyError(client: client, error: "wired.error.internal_error", message: message)
        }
    }

    func replyBanListError(client: Client, message: P7Message, error: BanListError) {
        switch error {
        case .invalidPattern, .invalidExpirationDate:
            self.replyError(client: client, error: "wired.error.invalid_message", message: message)
        case .alreadyExists:
            self.replyError(client: client, error: "wired.error.ban_exists", message: message)
        case .notFound:
            self.replyError(client: client, error: "wired.error.ban_not_found", message: message)
        }
    }

    // MARK: - Events

    func receiveEventGetFirstTime(client: Client, message: P7Message) {
        guard let user = client.user else {
            self.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard user.hasPrivilege(name: "wired.account.events.view_events") else {
            self.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        do {
            let reply = P7Message(withName: "wired.event.first_time", spec: client.socket.spec)
            reply.addParameter(
                field: "wired.event.first_time",
                value: try App.eventsController.firstEventDate() ?? Date(timeIntervalSince1970: 0)
            )
            self.reply(client: client, reply: reply, message: message)
        } catch {
            Logger.error("Failed to fetch first event time: \(error)")
            self.replyError(client: client, error: "wired.error.internal_error", message: message)
        }
    }

    func receiveEventGetEvents(client: Client, message: P7Message) {
        guard let user = client.user else {
            self.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard user.hasPrivilege(name: "wired.account.events.view_events") else {
            self.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        let fromTime = message.date(forField: "wired.event.from_time")
        let numberOfDays = message.uint32(forField: "wired.event.number_of_days") ?? 0
        let lastEventCount = message.uint32(forField: "wired.event.last_event_count") ?? 0

        self.recordEvent(.eventsGotEvents, client: client)

        do {
            let entries = try App.eventsController.listEvents(
                from: fromTime,
                numberOfDays: numberOfDays,
                lastEventCount: lastEventCount
            )

            for entry in entries {
                self.reply(
                    client: client,
                    reply: self.eventMessage(for: entry, name: "wired.event.event_list"),
                    message: message
                )
            }

            let done = P7Message(withName: "wired.event.event_list.done", spec: client.socket.spec)
            self.reply(client: client, reply: done, message: message)
        } catch {
            Logger.error("Failed to list events: \(error)")
            self.replyError(client: client, error: "wired.error.internal_error", message: message)
        }
    }

    func receiveEventSubscribe(client: Client, message: P7Message) {
        guard let user = client.user else {
            self.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard user.hasPrivilege(name: "wired.account.events.view_events") else {
            self.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        if client.isSubscribedToEvents {
            self.replyError(client: client, error: "wired.error.already_subscribed", message: message)
            return
        }

        client.isSubscribedToEvents = true
        self.replyOK(client: client, message: message)
    }

    func receiveEventUnsubscribe(client: Client, message: P7Message) {
        guard let user = client.user else {
            self.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard user.hasPrivilege(name: "wired.account.events.view_events") else {
            self.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        if !client.isSubscribedToEvents {
            self.replyError(client: client, error: "wired.error.not_subscribed", message: message)
            return
        }

        client.isSubscribedToEvents = false
        self.replyOK(client: client, message: message)
    }

    func receiveEventDeleteEvents(client: Client, message: P7Message) {
        guard let user = client.user else {
            self.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard user.hasPrivilege(name: "wired.account.events.view_events") else {
            self.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        let fromTime = message.date(forField: "wired.event.from_time")
        let toTime = message.date(forField: "wired.event.to_time")

        do {
            try App.eventsController.deleteEvents(from: fromTime, to: toTime)
            self.replyOK(client: client, message: message)
        } catch {
            Logger.error("Failed to delete events: \(error)")
            self.replyError(client: client, error: "wired.error.internal_error", message: message)
        }
    }

    // MARK: - Event recording (used by all domains)

    func recordEvent(
        _ event: WiredServerEvent,
        client: Client,
        parameters: [String] = [],
        loginOverride: String? = nil,
        nickOverride: String? = nil
    ) {
        let nick = nickOverride ?? client.nick ?? ""
        let login = loginOverride ?? client.user?.username ?? ""
        let ip = client.socket.getClientIP() ?? client.ip ?? ""
        self.recordEvent(event, nick: nick, login: login, ip: ip, parameters: parameters)
    }

    func recordEvent(
        _ event: WiredServerEvent,
        nick: String?,
        login: String?,
        ip: String,
        parameters: [String] = []
    ) {
        guard let eventsController = App?.eventsController else { return }

        do {
            let entry = try eventsController.addEvent(
                event,
                parameters: parameters,
                nick: nick ?? "",
                login: login ?? "",
                ip: ip
            )
            self.broadcastEvent(entry)
        } catch {
            Logger.error("Failed to record event \(event.protocolName): \(error)")
        }
    }

    private func eventMessage(for entry: EventEntry, name: String) -> P7Message {
        let reply = P7Message(withName: name, spec: self.spec)
        reply.addParameter(field: "wired.event.event", value: entry.eventCode)
        reply.addParameter(field: "wired.event.time", value: entry.time)
        if !entry.parameters.isEmpty {
            reply.addParameter(field: "wired.event.parameters", value: entry.parameters)
        }
        reply.addParameter(field: "wired.user.nick", value: entry.nick)
        reply.addParameter(field: "wired.user.login", value: entry.login)
        reply.addParameter(field: "wired.user.ip", value: entry.ip)
        return reply
    }

    private func broadcastEvent(_ entry: EventEntry) {
        let broadcast = self.eventMessage(for: entry, name: "wired.event.event")
        guard let clientsController = App?.clientsController else { return }
        for connectedClient in clientsController.connectedClientsSnapshot() {
            guard connectedClient.state == .LOGGED_IN else { continue }
            guard connectedClient.isSubscribedToEvents else { continue }
            guard let connectedUser = connectedClient.user else { continue }

            if !connectedUser.hasPrivilege(name: "wired.account.events.view_events") {
                connectedClient.isSubscribedToEvents = false
                continue
            }

            _ = self.send(message: broadcast, client: connectedClient)
        }
    }

    // MARK: - Settings

    func receiveGetSettings(client: Client, message: P7Message) {
        guard let user = client.user else { return }
        if !user.hasPrivilege(name: "wired.account.settings.get_settings") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        let response = P7Message(withName: "wired.settings.settings", spec: message.spec)
        response.addParameter(field: "wired.info.name", value: self.serverName)
        response.addParameter(field: "wired.info.description", value: self.serverDescription)

        if let bannerPath = bannerFilePath {
            if let data = readFileData(atPath: bannerPath) {
                response.addParameter(field: "wired.info.banner", value: data)
            }
        }

        response.addParameter(field: "wired.info.downloads", value: self.downloads)
        response.addParameter(field: "wired.info.uploads", value: self.uploads)
        response.addParameter(field: "wired.info.download_speed", value: self.downloadSpeed)
        response.addParameter(field: "wired.info.upload_speed", value: self.uploadSpeed)
        response.addParameter(field: "wired.settings.register_with_trackers", value: self.registerWithTrackers)
        response.addParameter(field: "wired.settings.trackers", value: self.trackers)
        response.addParameter(field: "wired.tracker.tracker", value: self.trackerEnabled)
        response.addParameter(field: "wired.tracker.categories", value: self.trackerCategories)

        self.reply(client: client, reply: response, message: message)
        self.recordEvent(.settingsGotSettings, client: client)
    }

    func receiveSetSettings(client: Client, message: P7Message) {
        var changed = false

        guard let user = client.user else { return }
        if !user.hasPrivilege(name: "wired.account.settings.set_settings") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        if let serverName = message.string(forField: "wired.info.name") {
            if self.serverName != serverName {
                self.serverName = serverName
                App.config["server", "name"] = serverName
                changed = true
            }
        }

        if let serverDescription = message.string(forField: "wired.info.description") {
            if self.serverDescription != serverDescription {
                self.serverDescription = serverDescription
                App.config["server", "description"] = serverDescription
                changed = true
            }
        }

        if let bannerPath = bannerFilePath {
            if let bannerData = message.data(forField: "wired.info.banner") {
                try? bannerData.write(to: URL(fileURLWithPath: bannerPath))
                changed = true
            }
        }

        if let downloads = message.uint32(forField: "wired.info.downloads"), self.downloads != downloads {
            self.downloads = downloads
            App.config["transfers", "downloads"] = downloads
            changed = true
        }

        if let uploads = message.uint32(forField: "wired.info.uploads"), self.uploads != uploads {
            self.uploads = uploads
            App.config["transfers", "uploads"] = uploads
            changed = true
        }

        if let downloadSpeed = message.uint32(forField: "wired.info.download_speed"), self.downloadSpeed != downloadSpeed {
            self.downloadSpeed = downloadSpeed
            App.config["transfers", "downloadSpeed"] = downloadSpeed
            changed = true
        }

        if let uploadSpeed = message.uint32(forField: "wired.info.upload_speed"), self.uploadSpeed != uploadSpeed {
            self.uploadSpeed = uploadSpeed
            App.config["transfers", "uploadSpeed"] = uploadSpeed
            changed = true
        }

        if let registerWithTrackers = message.bool(forField: "wired.settings.register_with_trackers"),
           self.registerWithTrackers != registerWithTrackers {
            self.registerWithTrackers = registerWithTrackers
            App.config["settings", "register_with_trackers"] = registerWithTrackers
            changed = true
        }

        if let trackers = message.stringList(forField: "wired.settings.trackers") {
            let normalized = trackers
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if self.trackers != normalized {
                self.trackers = normalized
                App.config["settings", "trackers"] = normalized
                changed = true
            }
        }

        if let trackerEnabled = message.bool(forField: "wired.tracker.tracker"), self.trackerEnabled != trackerEnabled {
            self.trackerEnabled = trackerEnabled
            App.config["tracker", "tracker"] = trackerEnabled
            changed = true
        }

        if let categories = message.stringList(forField: "wired.tracker.categories") {
            let normalized = categories
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if self.trackerCategories != normalized {
                self.trackerCategories = normalized
                App.config["tracker", "categories"] = normalized
                changed = true
            }
        }

        if changed {
            App.clientsController.broadcast(message: self.serverInfoMessage())
            App.outgoingTrackersController.refreshConfiguration(resetRegistrations: true)
        }

        App.serverController.replyOK(client: client, message: message)
        self.recordEvent(.settingsSetSettings, client: client)
    }

    // MARK: - Account listing

    func receiveAccountListUsers(client: Client, message: P7Message) {
        guard let user = client.user else { return }

        if !user.hasPrivilege(name: "wired.account.account.list_accounts") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        let users = App.usersController.users()
        let defaultDate = Date(timeIntervalSince1970: 0)

        for listedUser in users {
            guard let username = listedUser.username else { continue }

            let reply = P7Message(withName: "wired.account.user_list", spec: self.spec)
            reply.addParameter(field: "wired.account.name", value: username)
            reply.addParameter(field: "wired.account.full_name", value: listedUser.fullName ?? "")
            reply.addParameter(field: "wired.account.comment", value: listedUser.comment ?? "")
            reply.addParameter(field: "wired.account.creation_time", value: listedUser.creationTime ?? defaultDate)
            reply.addParameter(field: "wired.account.modification_time", value: listedUser.modificationTime ?? defaultDate)
            reply.addParameter(field: "wired.account.login_time", value: listedUser.loginTime ?? defaultDate)
            reply.addParameter(field: "wired.account.edited_by", value: listedUser.editedBy ?? "")
            let downloads = UInt32(clamping: Int(listedUser.downloads ?? 0))
            let downloadTransferred = UInt64(clamping: Int(listedUser.downloadTransferred ?? 0))
            let uploads = UInt32(clamping: Int(listedUser.uploads ?? 0))
            let uploadTransferred = UInt64(clamping: Int(listedUser.uploadTransferred ?? 0))

            reply.addParameter(field: "wired.account.downloads", value: downloads)
            reply.addParameter(field: "wired.account.download_transferred", value: downloadTransferred)
            reply.addParameter(field: "wired.account.uploads", value: uploads)
            reply.addParameter(field: "wired.account.upload_transferred", value: uploadTransferred)
            reply.addParameter(field: "wired.account.group", value: listedUser.group ?? "")
            reply.addParameter(field: "wired.account.groups", value: listedUser.groups?
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty } ?? [])
            // SECURITY: password hash intentionally omitted (FINDING_A_003)
            reply.addParameter(field: "wired.account.color", value: UInt32(listedUser.color ?? "") ?? 0)

            self.reply(client: client, reply: reply, message: message)
        }

        let done = P7Message(withName: "wired.account.user_list.done", spec: self.spec)
        self.reply(client: client, reply: done, message: message)
        self.recordEvent(.accountListedUsers, client: client)
    }

    func receiveAccountListGroups(client: Client, message: P7Message) {
        guard let user = client.user else { return }

        if !user.hasPrivilege(name: "wired.account.account.list_accounts") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        let groups = App.usersController.groups()
        let defaultDate = Date(timeIntervalSince1970: 0)

        for listedGroup in groups {
            guard let groupName = listedGroup.name else { continue }

            let reply = P7Message(withName: "wired.account.group_list", spec: self.spec)
            reply.addParameter(field: "wired.account.name", value: groupName)
            reply.addParameter(field: "wired.account.comment", value: "")
            reply.addParameter(field: "wired.account.creation_time", value: defaultDate)
            reply.addParameter(field: "wired.account.modification_time", value: defaultDate)
            reply.addParameter(field: "wired.account.edited_by", value: "")
            reply.addParameter(field: "wired.account.color", value: UInt32(listedGroup.color ?? "") ?? 0)

            self.reply(client: client, reply: reply, message: message)
        }

        let done = P7Message(withName: "wired.account.group_list.done", spec: self.spec)
        self.reply(client: client, reply: done, message: message)
        self.recordEvent(.accountListedGroups, client: client)
    }

    // MARK: - Account CRUD

    func receiveAccountCreateUser(client: Client, message: P7Message) {
        guard let requestingUser = client.user else { return }

        if !requestingUser.hasPrivilege(name: "wired.account.account.create_users") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let name = message.string(forField: "wired.account.name")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty,
              let password = message.string(forField: "wired.account.password"),
              !password.isEmpty else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        if App.usersController.user(withUsername: name) != nil {
            App.serverController.replyError(client: client, error: "wired.error.account_exists", message: message)
            return
        }

        let primaryGroup = message.string(forField: "wired.account.group") ?? ""
        let secondaryGroups = message.stringList(forField: "wired.account.groups") ?? []
        if !primaryGroup.isEmpty && App.usersController.group(withName: primaryGroup) == nil {
            App.serverController.replyError(client: client, error: "wired.error.account_not_found", message: message)
            return
        }
        if secondaryGroups.contains(where: { !$0.isEmpty && App.usersController.group(withName: $0) == nil }) {
            App.serverController.replyError(client: client, error: "wired.error.account_not_found", message: message)
            return
        }

        let normalizedPassword = normalizedPasswordForStorage(password)
        let account = User(username: name, password: normalizedPassword.hash)
        account.passwordSalt = normalizedPassword.salt
        account.fullName = message.string(forField: "wired.account.full_name") ?? ""
        account.comment = message.string(forField: "wired.account.comment") ?? ""
        account.group = primaryGroup
        account.groups = secondaryGroups.joined(separator: ", ")
        account.files = message.string(forField: "wired.account.files")
        account.creationTime = Date()
        account.modificationTime = account.creationTime
        account.editedBy = requestingUser.username ?? ""

        if let identity = message.string(forField: "wired.account.identity")?.trimmingCharacters(in: .whitespacesAndNewlines),
           !identity.isEmpty {
            if !App.usersController.isIdentityAvailable(identity) {
                App.serverController.replyError(client: client, error: "wired.error.account_exists", message: message)
                return
            }
            account.identity = identity
        }

        if let color = message.enumeration(forField: "wired.account.color")
            ?? message.uint32(forField: "wired.account.color") {
            account.color = String(color)
        }

        guard App.usersController.save(user: account) else {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        var privilegesSaved = true
        var deniedPrivilegeGrant = false
        for privilege in self.accountPrivilegesIncludingColor() {
            guard let field = spec?.fieldsByName[privilege] else { continue }
            guard field.type == .bool else { continue }
            if let value = message.bool(forField: privilege) {
                if value
                    && !requestingUser.hasPrivilege(name: privilege)
                    && !requestingUser.hasPrivilege(name: "wired.account.account.raise_account_privileges") {
                    deniedPrivilegeGrant = true
                    privilegesSaved = false
                    continue
                }
                if !App.usersController.setUserPrivilege(privilege, value: value, for: account) {
                    privilegesSaved = false
                }
            }
        }

        if !privilegesSaved {
            _ = App.usersController.delete(user: account)
            App.serverController.replyError(client: client, error: deniedPrivilegeGrant ? "wired.error.permission_denied" : "wired.error.internal_error", message: message)
            return
        }

        App.serverController.replyOK(client: client, message: message)
        self.broadcastAccountsChangedToSubscribers()
        self.recordEvent(.accountCreatedUser, client: client, parameters: [name])
    }

    func receiveAccountCreateGroup(client: Client, message: P7Message) {
        guard let requestingUser = client.user else { return }

        if !requestingUser.hasPrivilege(name: "wired.account.account.create_groups") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let name = message.string(forField: "wired.account.name")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        if App.usersController.group(withName: name) != nil {
            App.serverController.replyError(client: client, error: "wired.error.account_exists", message: message)
            return
        }

        let account = Group(name: name)
        if let color = message.enumeration(forField: "wired.account.color")
            ?? message.uint32(forField: "wired.account.color") {
            account.color = String(color)
        }

        guard App.usersController.save(group: account) else {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        var privilegesSaved = true
        var deniedPrivilegeGrant = false
        for privilege in self.accountPrivilegesIncludingColor() {
            guard let field = spec?.fieldsByName[privilege] else { continue }
            guard field.type == .bool else { continue }
            if let value = message.bool(forField: privilege) {
                if value
                    && !requestingUser.hasPrivilege(name: privilege)
                    && !requestingUser.hasPrivilege(name: "wired.account.account.raise_account_privileges") {
                    deniedPrivilegeGrant = true
                    privilegesSaved = false
                    continue
                }
                if !App.usersController.setGroupPrivilege(privilege, value: value, for: account) {
                    privilegesSaved = false
                }
            }
        }

        if !privilegesSaved {
            _ = App.usersController.delete(group: account)
            App.serverController.replyError(client: client, error: deniedPrivilegeGrant ? "wired.error.permission_denied" : "wired.error.internal_error", message: message)
            return
        }

        App.serverController.replyOK(client: client, message: message)
        self.broadcastAccountsChangedToSubscribers()
        self.recordEvent(.accountCreatedGroup, client: client, parameters: [name])
    }

    func receiveAccountChangePassword(client: Client, message: P7Message) {
        guard let requestingUser = client.user else { return }

        if !requestingUser.hasPrivilege(name: "wired.account.account.change_password") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let password = message.string(forField: "wired.account.password"), !password.isEmpty else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let account = App.usersController.user(withUsername: requestingUser.username ?? "") else {
            App.serverController.replyError(client: client, error: "wired.error.account_not_found", message: message)
            return
        }

        let result = normalizedPasswordForStorage(password)
        account.password = result.hash
        account.passwordSalt = result.salt
        account.isLegacy = false

        guard App.usersController.save(user: account) else {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        Logger.info("Password changed for user '\(requestingUser.username ?? "")'")

        let reply = P7Message(withName: "wired.okay", spec: self.spec)
        App.serverController.reply(client: client, reply: reply, message: message)
        self.recordEvent(.accountChangedPassword, client: client)
    }

    func receiveAccountReadUser(client: Client, message: P7Message) {
        guard let requestingUser = client.user else { return }

        if !requestingUser.hasPrivilege(name: "wired.account.account.read_accounts") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let name = message.string(forField: "wired.account.name"), !name.isEmpty else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let account = App.usersController.userWithPrivileges(withUsername: name) else {
            App.serverController.replyError(client: client, error: "wired.error.account_not_found", message: message)
            return
        }

        let reply = accountUserMessage(for: account, name: "wired.account.user")
        self.reply(client: client, reply: reply, message: message)
        self.recordEvent(.accountReadUser, client: client, parameters: [name])
    }

    func receiveAccountReadGroup(client: Client, message: P7Message) {
        guard let requestingUser = client.user else { return }

        if !requestingUser.hasPrivilege(name: "wired.account.account.read_accounts") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let name = message.string(forField: "wired.account.name"), !name.isEmpty else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let account = App.usersController.groupWithPrivileges(withName: name) else {
            App.serverController.replyError(client: client, error: "wired.error.account_not_found", message: message)
            return
        }

        let reply = accountGroupMessage(for: account, name: "wired.account.group")
        self.reply(client: client, reply: reply, message: message)
        self.recordEvent(.accountReadGroup, client: client, parameters: [name])
    }

    func receiveAccountEditUser(client: Client, message: P7Message) {
        guard let requestingUser = client.user else { return }

        if !requestingUser.hasPrivilege(name: "wired.account.account.edit_users") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let name = message.string(forField: "wired.account.name"), !name.isEmpty else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let account = App.usersController.userWithPrivileges(withUsername: name) else {
            App.serverController.replyError(client: client, error: "wired.error.account_not_found", message: message)
            return
        }

        // SECURITY (FINDING_F_006): Prevent non-admin users from editing the "admin" account
        if name == "admin" && requestingUser.username != "admin" {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        if let newName = message.string(forField: "wired.account.new_name"), !newName.isEmpty, newName != name {
            if App.usersController.user(withUsername: newName) != nil {
                App.serverController.replyError(client: client, error: "wired.error.account_exists", message: message)
                return
            }
            account.username = newName
        }

        if let fullName = message.string(forField: "wired.account.full_name") {
            account.fullName = fullName
        }
        if let comment = message.string(forField: "wired.account.comment") {
            account.comment = comment
        }
        var passwordChanged = false
        if let password = message.string(forField: "wired.account.password"), !password.isEmpty {
            let result = normalizedPasswordForStorage(password)
            if result.hash != account.password {
                account.password = result.hash
                account.passwordSalt = result.salt
                passwordChanged = true
            }
        }
        if let group = message.string(forField: "wired.account.group") {
            account.group = group
        }
        if let secondaryGroups = message.stringList(forField: "wired.account.groups") {
            account.groups = secondaryGroups.joined(separator: ", ")
        }

        account.editedBy = requestingUser.username ?? ""
        account.modificationTime = Date()

        var privilegesSaved = true
        var deniedPrivilegeGrant = false

        for privilege in self.accountPrivilegesIncludingColor() {
            guard let field = spec?.fieldsByName[privilege] else { continue }
            switch field.type {
            case .bool:
                if let value = message.bool(forField: privilege) {
                    // SECURITY (FINDING_F_006): Cannot grant a privilege the editing user does not possess
                    if value == true
                        && !requestingUser.hasPrivilege(name: privilege)
                        && !requestingUser.hasPrivilege(name: "wired.account.account.raise_account_privileges") {
                        deniedPrivilegeGrant = true
                        continue
                    }
                    if !App.usersController.setUserPrivilege(privilege, value: value, for: account) {
                        privilegesSaved = false
                    }
                }
            case .enum32, .uint32:
                if privilege == "wired.account.color", let value = message.uint32(forField: privilege) {
                    account.color = String(value)
                }
            default:
                break
            }
        }

        if let color = message.enumeration(forField: "wired.account.color")
            ?? message.uint32(forField: "wired.account.color") {
            account.color = String(color)
        }

        if !privilegesSaved {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        if deniedPrivilegeGrant {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        if !App.usersController.save(user: account) {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        App.serverController.replyOK(client: client, message: message)

        let updatedName = account.username ?? name
        if updatedName != name {
            self.broadcastAccountsChangedToSubscribers()
        }

        self.recordEvent(.accountEditedUser, client: client, parameters: [updatedName])

        // SECURITY (FINDING_A_016): Invalidate other sessions after password change
        if passwordChanged {
            let targetName = normalizedAccountIdentifier(updatedName)
            for connectedClient in App.clientsController.connectedClientsSnapshot() {
                guard connectedClient.state == .LOGGED_IN else { continue }
                guard connectedClient.userID != client.userID else { continue }
                guard let connectedUsername = connectedClient.user?.username else { continue }
                if normalizedAccountIdentifier(connectedUsername) == targetName {
                    self.disconnectClient(client: connectedClient)
                }
            }
        }

        self.reloadPrivilegesForLoggedInUsers(matchingAccountNames: [name, updatedName])
    }

    func receiveAccountEditGroup(client: Client, message: P7Message) {
        guard let requestingUser = client.user else { return }

        if !requestingUser.hasPrivilege(name: "wired.account.account.edit_groups") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let name = message.string(forField: "wired.account.name"), !name.isEmpty else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let account = App.usersController.groupWithPrivileges(withName: name) else {
            App.serverController.replyError(client: client, error: "wired.error.account_not_found", message: message)
            return
        }

        if let newName = message.string(forField: "wired.account.new_name"), !newName.isEmpty, newName != name {
            if App.usersController.group(withName: newName) != nil {
                App.serverController.replyError(client: client, error: "wired.error.account_exists", message: message)
                return
            }
            account.name = newName
        }

        var privilegesSaved = true
        var deniedPrivilegeGrant = false

        for privilege in self.accountPrivilegesIncludingColor() {
            guard let field = spec?.fieldsByName[privilege] else { continue }
            switch field.type {
            case .bool:
                if let value = message.bool(forField: privilege) {
                    if value == true
                        && !requestingUser.hasPrivilege(name: privilege)
                        && !requestingUser.hasPrivilege(name: "wired.account.account.raise_account_privileges") {
                        deniedPrivilegeGrant = true
                        continue
                    }
                    if !App.usersController.setGroupPrivilege(privilege, value: value, for: account) {
                        privilegesSaved = false
                    }
                }
            case .enum32, .uint32:
                if privilege == "wired.account.color", let value = message.uint32(forField: privilege) {
                    account.color = String(value)
                }
            default:
                break
            }
        }

        if let color = message.enumeration(forField: "wired.account.color")
            ?? message.uint32(forField: "wired.account.color") {
            account.color = String(color)
        }

        if !privilegesSaved {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        if deniedPrivilegeGrant {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        if !App.usersController.save(group: account) {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        App.serverController.replyOK(client: client, message: message)

        let updatedName = account.name ?? name
        if updatedName != name {
            self.broadcastAccountsChangedToSubscribers()
        }

        self.recordEvent(.accountEditedGroup, client: client, parameters: [updatedName])

        self.reloadPrivilegesForLoggedInUsers(affectedByGroups: [name, updatedName])
    }

    func receiveAccountDeleteUser(client: Client, message: P7Message) {
        guard let requestingUser = client.user else { return }

        if !requestingUser.hasPrivilege(name: "wired.account.account.delete_users") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let name = message.string(forField: "wired.account.name"), !name.isEmpty,
              let disconnectUsers = message.bool(forField: "wired.account.disconnect_users") else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let account = App.usersController.userWithPrivileges(withUsername: name) else {
            App.serverController.replyError(client: client, error: "wired.error.account_not_found", message: message)
            return
        }

        if name == "admin" && requestingUser.username != "admin" {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        let targetName = normalizedAccountIdentifier(name)
        let connectedClients = App.clientsController.connectedClientsSnapshot().filter { connectedClient in
            guard connectedClient.state == .LOGGED_IN else { return false }
            guard let connectedName = connectedClient.user?.username else { return false }
            return normalizedAccountIdentifier(connectedName) == targetName
        }

        if !disconnectUsers && !connectedClients.isEmpty {
            App.serverController.replyError(client: client, error: "wired.error.account_in_use", message: message)
            return
        }

        guard App.usersController.delete(user: account) else {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        App.serverController.replyOK(client: client, message: message)
        for connectedClient in connectedClients {
            self.disconnectClient(client: connectedClient)
        }

        self.broadcastAccountsChangedToSubscribers()
        self.recordEvent(.accountDeletedUser, client: client, parameters: [name])
    }

    func receiveAccountDeleteGroup(client: Client, message: P7Message) {
        guard let requestingUser = client.user else { return }

        if !requestingUser.hasPrivilege(name: "wired.account.account.delete_groups") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let name = message.string(forField: "wired.account.name"), !name.isEmpty else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let account = App.usersController.groupWithPrivileges(withName: name) else {
            App.serverController.replyError(client: client, error: "wired.error.account_not_found", message: message)
            return
        }

        guard App.usersController.delete(group: account) else {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        App.serverController.replyOK(client: client, message: message)
        self.broadcastAccountsChangedToSubscribers()
        self.recordEvent(.accountDeletedGroup, client: client, parameters: [name])
        self.reloadPrivilegesForLoggedInUsers(affectedByGroups: [name])
    }

    func receiveAccountSubscribeAccounts(client: Client, message: P7Message) {
        guard let user = client.user else { return }

        if !user.hasPrivilege(name: "wired.account.account.list_accounts") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        if client.isSubscribedToAccounts {
            App.serverController.replyError(client: client, error: "wired.error.already_subscribed", message: message)
            return
        }

        client.isSubscribedToAccounts = true
        App.serverController.replyOK(client: client, message: message)
    }

    func receiveAccountUnsubscribeAccounts(client: Client, message: P7Message) {
        guard let user = client.user else { return }

        if !user.hasPrivilege(name: "wired.account.account.list_accounts") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        if !client.isSubscribedToAccounts {
            App.serverController.replyError(client: client, error: "wired.error.not_subscribed", message: message)
            return
        }

        client.isSubscribedToAccounts = false
        App.serverController.replyOK(client: client, message: message)
    }

    // MARK: - Account message helpers

    private func accountUserMessage(for account: User, name: String) -> P7Message {
        let defaultDate = Date(timeIntervalSince1970: 0)
        let reply = P7Message(withName: name, spec: self.spec)

        reply.addParameter(field: "wired.account.name", value: account.username ?? "")
        reply.addParameter(field: "wired.account.full_name", value: account.fullName ?? "")
        reply.addParameter(field: "wired.account.comment", value: account.comment ?? "")
        reply.addParameter(field: "wired.account.password", value: account.password ?? "")
        reply.addParameter(field: "wired.account.group", value: account.group ?? "")
        reply.addParameter(field: "wired.account.groups", value: account.groups?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? [])
        reply.addParameter(field: "wired.account.creation_time", value: account.creationTime ?? defaultDate)
        reply.addParameter(field: "wired.account.modification_time", value: account.modificationTime ?? defaultDate)
        reply.addParameter(field: "wired.account.login_time", value: account.loginTime ?? defaultDate)
        reply.addParameter(field: "wired.account.edited_by", value: account.editedBy ?? "")
        reply.addParameter(field: "wired.account.downloads", value: UInt32(clamping: Int(account.downloads ?? 0)))
        reply.addParameter(field: "wired.account.uploads", value: UInt32(clamping: Int(account.uploads ?? 0)))
        reply.addParameter(field: "wired.account.download_transferred",
                           value: UInt64(clamping: Int(account.downloadTransferred ?? 0)))
        reply.addParameter(field: "wired.account.upload_transferred",
                           value: UInt64(clamping: Int(account.uploadTransferred ?? 0)))

        for privilege in self.accountPrivilegesIncludingColor() {
            guard let field = spec?.fieldsByName[privilege] else { continue }
            switch field.type {
            case .bool:
                reply.addParameter(field: privilege, value: account.hasPrivilege(name: privilege))
            case .enum32, .uint32:
                if privilege == "wired.account.color" {
                    reply.addParameter(field: privilege, value: UInt32(account.color ?? "") ?? 0)
                } else {
                    reply.addParameter(field: privilege, value: UInt32(0))
                }
            default:
                break
            }
        }

        return reply
    }

    private func accountGroupMessage(for account: Group, name: String) -> P7Message {
        let defaultDate = Date(timeIntervalSince1970: 0)
        let reply = P7Message(withName: name, spec: self.spec)

        reply.addParameter(field: "wired.account.name", value: account.name ?? "")
        reply.addParameter(field: "wired.account.comment", value: "")
        reply.addParameter(field: "wired.account.creation_time", value: defaultDate)
        reply.addParameter(field: "wired.account.modification_time", value: defaultDate)
        reply.addParameter(field: "wired.account.edited_by", value: "")

        let privilegesByName = Dictionary(uniqueKeysWithValues:
            account.privileges.map { (($0.name ?? ""), $0.value ?? false) })

        for privilege in self.accountPrivilegesIncludingColor() {
            guard let field = spec?.fieldsByName[privilege] else { continue }
            switch field.type {
            case .bool:
                reply.addParameter(field: privilege, value: privilegesByName[privilege] ?? false)
            case .enum32, .uint32:
                if privilege == "wired.account.color" {
                    reply.addParameter(field: privilege, value: UInt32(account.color ?? "") ?? 0)
                } else {
                    reply.addParameter(field: privilege, value: UInt32(0))
                }
            default:
                break
            }
        }

        return reply
    }

    // MARK: - Account privilege helpers

    func accountPrivilegesMessage(for account: User) -> P7Message {
        let reply = P7Message(withName: "wired.account.privileges", spec: self.spec)
        let privilegesByName = Dictionary(uniqueKeysWithValues:
            account.privileges.map { (($0.name ?? ""), $0.value ?? false) })

        reply.addParameter(field: "wired.account.name", value: account.username ?? "")
        reply.addParameter(field: "wired.account.group", value: account.group ?? "")
        reply.addParameter(field: "wired.account.groups",
                           value: account.groups?
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty } ?? [])

        for privilege in self.accountPrivilegesIncludingColor() {
            guard let field = spec?.fieldsByName[privilege] else { continue }
            switch field.type {
            case .bool:
                reply.addParameter(field: privilege, value: privilegesByName[privilege] ?? false)
            case .enum32, .uint32:
                if privilege == "wired.account.color" {
                    reply.addParameter(field: privilege, value: UInt32(account.color ?? "") ?? 0)
                } else {
                    reply.addParameter(field: privilege, value: UInt32(0))
                }
            default:
                break
            }
        }

        return reply
    }

    private func accountPrivilegesIncludingColor() -> [String] {
        var privileges = spec?.accountPrivileges ?? []

        if spec?.fieldsByName["wired.account.color"] != nil,
           !privileges.contains("wired.account.color") {
            privileges.append("wired.account.color")
        }

        return privileges
    }

    // SECURITY (FINDING_A_004): Salted SHA-256 password storage
    private func normalizedPasswordForStorage(_ password: String) -> (hash: String, salt: String) {
        let isHexSHA256 = password.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil
        let hash = isHexSHA256 ? password.lowercased() : password.sha256()
        let salt = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        return (hash: hash, salt: salt)
    }

    private func broadcastAccountsChangedToSubscribers() {
        let broadcast = P7Message(withName: "wired.account.accounts_changed", spec: self.spec)

        for connectedClient in App.clientsController.connectedClientsSnapshot() {
            guard connectedClient.state == .LOGGED_IN else { continue }
            guard connectedClient.isSubscribedToAccounts else { continue }
            guard let user = connectedClient.user else { continue }

            if !user.hasPrivilege(name: "wired.account.account.list_accounts") {
                connectedClient.isSubscribedToAccounts = false
                continue
            }

            _ = self.send(message: broadcast, client: connectedClient)
        }
    }

    private func reloadPrivilegesForLoggedInUsers(matchingAccountNames accountNames: [String]) {
        let normalizedNames = Set(accountNames.map { normalizedAccountIdentifier($0) }.filter { !$0.isEmpty })
        guard !normalizedNames.isEmpty else { return }

        for connectedClient in App.clientsController.connectedClientsSnapshot() {
            guard connectedClient.state == .LOGGED_IN else { continue }
            guard let currentName = connectedClient.user?.username else { continue }
            let normalizedCurrentName = normalizedAccountIdentifier(currentName)
            guard normalizedNames.contains(normalizedCurrentName) else { continue }

            guard let refreshedUser = userWithPrivileges(matchingUsername: currentName) else { continue }

            let hadOfflineList = connectedClient.user?.hasPrivilege(name: "wired.account.user.list_offline_users") ?? false
            connectedClient.user = refreshedUser

            if !refreshedUser.hasPrivilege(name: "wired.account.account.list_accounts") {
                connectedClient.isSubscribedToAccounts = false
            }

            if !refreshedUser.hasPrivilege(name: "wired.account.events.view_events") {
                connectedClient.isSubscribedToEvents = false
            }

            if !refreshedUser.hasPrivilege(name: "wired.account.log.view_log") {
                connectedClient.isSubscribedToLog = false
            }

            _ = self.send(message: self.accountPrivilegesMessage(for: refreshedUser), client: connectedClient)

            // If the offline-list privilege was just granted, push the current
            // list so the client doesn't have to reconnect to populate the panel.
            let hasOfflineList = refreshedUser.hasPrivilege(name: "wired.account.user.list_offline_users")
            if !hadOfflineList && hasOfflineList {
                self.sendOfflineUserList(to: connectedClient)
            }
        }
    }

    private func reloadPrivilegesForLoggedInUsers(affectedByGroups groupNames: [String]) {
        let normalizedNames = Set(groupNames.map { normalizedAccountIdentifier($0) }.filter { !$0.isEmpty })
        guard !normalizedNames.isEmpty else { return }

        for connectedClient in App.clientsController.connectedClientsSnapshot() {
            guard connectedClient.state == .LOGGED_IN else { continue }
            guard let currentUser = connectedClient.user else { continue }
            guard let username = currentUser.username else { continue }

            let currentGroups = normalizedGroupIdentifiers(for: currentUser)
            let wasInAffectedGroup = !currentGroups.isDisjoint(with: normalizedNames)
            guard wasInAffectedGroup else { continue }

            guard let refreshedUser = userWithPrivileges(matchingUsername: username) else { continue }
            let hadOfflineList = currentUser.hasPrivilege(name: "wired.account.user.list_offline_users")
            connectedClient.user = refreshedUser

            if !refreshedUser.hasPrivilege(name: "wired.account.account.list_accounts") {
                connectedClient.isSubscribedToAccounts = false
            }

            if !refreshedUser.hasPrivilege(name: "wired.account.events.view_events") {
                connectedClient.isSubscribedToEvents = false
            }

            if !refreshedUser.hasPrivilege(name: "wired.account.log.view_log") {
                connectedClient.isSubscribedToLog = false
            }

            _ = self.send(message: self.accountPrivilegesMessage(for: refreshedUser), client: connectedClient)

            let hasOfflineList = refreshedUser.hasPrivilege(name: "wired.account.user.list_offline_users")
            if !hadOfflineList && hasOfflineList {
                self.sendOfflineUserList(to: connectedClient)
            }
        }
    }

    private func normalizedAccountIdentifier(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func normalizedGroupIdentifiers(for user: User) -> Set<String> {
        var groups = Set<String>()

        if let primary = user.group {
            let normalized = normalizedAccountIdentifier(primary)
            if !normalized.isEmpty {
                groups.insert(normalized)
            }
        }

        if let secondaryGroups = user.groups {
            for raw in secondaryGroups.split(separator: ",") {
                let normalized = normalizedAccountIdentifier(String(raw))
                if !normalized.isEmpty {
                    groups.insert(normalized)
                }
            }
        }

        return groups
    }

    private func userWithPrivileges(matchingUsername username: String) -> User? {
        if let exact = App.usersController.userWithPrivileges(withUsername: username) {
            return exact
        }

        let normalizedUsername = normalizedAccountIdentifier(username)
        guard !normalizedUsername.isEmpty else { return nil }

        for listedUser in App.usersController.users() {
            guard let listedUsername = listedUser.username else { continue }
            if normalizedAccountIdentifier(listedUsername) == normalizedUsername {
                return App.usersController.userWithPrivileges(withUsername: listedUsername)
            }
        }

        return nil
    }
}
