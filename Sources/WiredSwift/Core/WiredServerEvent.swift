// swiftlint:disable cyclomatic_complexity
// TODO: Replace the large switch in WiredServerEvent with a dispatch table
import Foundation

public enum WiredServerEventCategory: String, CaseIterable, Sendable {
    case users
    case files
    case accounts
    case messages
    case boards
    case downloads
    case uploads
    case administration
    case tracker

    public var systemImageName: String {
        switch self {
        case .users: return "person.2.fill"
        case .files: return "folder.fill"
        case .accounts: return "person.crop.rectangle.fill"
        case .messages: return "message.fill"
        case .boards: return "text.bubble.fill"
        case .downloads: return "arrow.down.circle.fill"
        case .uploads: return "arrow.up.circle.fill"
        case .administration: return "gearshape.fill"
        case .tracker: return "antenna.radiowaves.left.and.right"
        }
    }

    public var title: String {
        switch self {
        case .users: return "Users"
        case .files: return "Files"
        case .accounts: return "Accounts"
        case .messages: return "Messages"
        case .boards: return "Boards"
        case .downloads: return "Downloads"
        case .uploads: return "Uploads"
        case .administration: return "Administration"
        case .tracker: return "Tracker"
        }
    }
}

public enum WiredServerEvent: UInt32, CaseIterable, Sendable {
    case userLoggedIn = 0
    case userLoginFailed = 1
    case userLoggedOut = 2
    case userChangedNick = 3
    case userGotInfo = 4
    case userDisconnectedUser = 5
    case userBannedUser = 6
    case userGotUsers = 7
    case fileListedDirectory = 8
    case fileGotInfo = 9
    case fileMoved = 10
    case fileLinked = 11
    case fileSetType = 12
    case fileSetComment = 13
    case fileSetExecutable = 14
    case fileSetPermissions = 15
    case fileSetLabel = 16
    case fileDeleted = 17
    case fileCreatedDirectory = 18
    case fileSearched = 19
    case filePreviewedFile = 20
    case accountChangedPassword = 21
    case accountListedUsers = 22
    case accountListedGroups = 23
    case accountReadUser = 24
    case accountReadGroup = 25
    case accountCreatedUser = 26
    case accountCreatedGroup = 27
    case accountEditedUser = 28
    case accountEditedGroup = 29
    case accountDeletedUser = 30
    case accountDeletedGroup = 31
    case messageSent = 32
    case messageBroadcasted = 33
    case boardGotBoards = 34
    case boardGotThreads = 35
    case boardGotThread = 36
    case boardAddedBoard = 37
    case boardRenamedBoard = 38
    case boardMovedBoard = 39
    case boardDeletedBoard = 40
    case boardGotBoardInfo = 41
    case boardSetBoardInfo = 42
    case boardAddedThread = 43
    case boardEditedThread = 44
    case boardMovedThread = 45
    case boardDeletedThread = 46
    case boardAddedPost = 47
    case boardEditedPost = 48
    case boardDeletedPost = 49
    case boardSearched = 67
    case transferStartedFileDownload = 50
    case transferStoppedFileDownload = 51
    case transferCompletedFileDownload = 52
    case transferStartedFileUpload = 53
    case transferStoppedFileUpload = 54
    case transferCompletedFileUpload = 55
    case transferCompletedDirectoryUpload = 56
    case logGotLog = 57
    case eventsGotEvents = 58
    case settingsGotSettings = 59
    case settingsSetSettings = 60
    case banlistGotBans = 61
    case banlistAddedBan = 62
    case banlistDeletedBan = 63
    case trackerGotCategories = 64
    case trackerGotServers = 65
    case trackerRegisteredServer = 66

    public var protocolName: String {
        switch self {
        case .userLoggedIn: return "wired.event.user.logged_in"
        case .userLoginFailed: return "wired.event.user.login_failed"
        case .userLoggedOut: return "wired.event.user.logged_out"
        case .userChangedNick: return "wired.event.user.changed_nick"
        case .userGotInfo: return "wired.event.user.got_info"
        case .userDisconnectedUser: return "wired.event.user.disconnected_user"
        case .userBannedUser: return "wired.event.user.banned_user"
        case .userGotUsers: return "wired.event.user.got_users"
        case .fileListedDirectory: return "wired.event.file.listed_directory"
        case .fileGotInfo: return "wired.event.file.got_info"
        case .fileMoved: return "wired.event.file.moved"
        case .fileLinked: return "wired.event.file.linked"
        case .fileSetType: return "wired.event.file.set_type"
        case .fileSetComment: return "wired.event.file.set_comment"
        case .fileSetExecutable: return "wired.event.file.set_executable"
        case .fileSetPermissions: return "wired.event.file.set_permissions"
        case .fileSetLabel: return "wired.event.file.set_label"
        case .fileDeleted: return "wired.event.file.deleted"
        case .fileCreatedDirectory: return "wired.event.file.created_directory"
        case .fileSearched: return "wired.event.file.searched"
        case .filePreviewedFile: return "wired.event.file.previewed_file"
        case .accountChangedPassword: return "wired.event.account.changed_password"
        case .accountListedUsers: return "wired.event.account.listed_users"
        case .accountListedGroups: return "wired.event.account.listed_groups"
        case .accountReadUser: return "wired.event.account.read_user"
        case .accountReadGroup: return "wired.event.account.read_group"
        case .accountCreatedUser: return "wired.event.account.created_user"
        case .accountCreatedGroup: return "wired.event.account.created_group"
        case .accountEditedUser: return "wired.event.account.edited_user"
        case .accountEditedGroup: return "wired.event.account.edited_group"
        case .accountDeletedUser: return "wired.event.account.deleted_user"
        case .accountDeletedGroup: return "wired.event.account.deleted_group"
        case .messageSent: return "wired.event.message.sent"
        case .messageBroadcasted: return "wired.event.message.broadcasted"
        case .boardGotBoards: return "wired.event.board.got_boards"
        case .boardGotThreads: return "wired.event.board.got_threads"
        case .boardGotThread: return "wired.event.board.got_thread"
        case .boardAddedBoard: return "wired.event.board.added_board"
        case .boardRenamedBoard: return "wired.event.board.renamed_board"
        case .boardMovedBoard: return "wired.event.board.moved_board"
        case .boardDeletedBoard: return "wired.event.board.deleted_board"
        case .boardGotBoardInfo: return "wired.event.board.got_board_info"
        case .boardSetBoardInfo: return "wired.event.board.set_board_info"
        case .boardAddedThread: return "wired.event.board.added_thread"
        case .boardEditedThread: return "wired.event.board.edited_thread"
        case .boardMovedThread: return "wired.event.board.moved_thread"
        case .boardDeletedThread: return "wired.event.board.deleted_thread"
        case .boardAddedPost: return "wired.event.board.added_post"
        case .boardEditedPost: return "wired.event.board.edited_post"
        case .boardDeletedPost: return "wired.event.board.deleted_post"
        case .boardSearched: return "wired.event.board.searched"
        case .transferStartedFileDownload: return "wired.event.transfer.started_file_download"
        case .transferStoppedFileDownload: return "wired.event.transfer.stopped_file_download"
        case .transferCompletedFileDownload: return "wired.event.transfer.completed_file_download"
        case .transferStartedFileUpload: return "wired.event.transfer.started_file_upload"
        case .transferStoppedFileUpload: return "wired.event.transfer.stopped_file_upload"
        case .transferCompletedFileUpload: return "wired.event.transfer.completed_file_upload"
        case .transferCompletedDirectoryUpload: return "wired.event.transfer.completed_directory_upload"
        case .logGotLog: return "wired.event.log.got_log"
        case .eventsGotEvents: return "wired.event.events.got_events"
        case .settingsGotSettings: return "wired.event.settings.got_settings"
        case .settingsSetSettings: return "wired.event.settings.set_settings"
        case .banlistGotBans: return "wired.event.banlist.got_bans"
        case .banlistAddedBan: return "wired.event.banlist.added_ban"
        case .banlistDeletedBan: return "wired.event.banlist.deleted_ban"
        case .trackerGotCategories: return "wired.event.tracker.got_categories"
        case .trackerGotServers: return "wired.event.tracker.got_servers"
        case .trackerRegisteredServer: return "wired.event.tracker.registered_server"
        }
    }

    public var category: WiredServerEventCategory {
        switch self {
        case .userLoggedIn, .userLoginFailed, .userLoggedOut, .userChangedNick, .userGotInfo,
             .userDisconnectedUser, .userBannedUser, .userGotUsers:
            return .users
        case .fileListedDirectory, .fileGotInfo, .fileMoved, .fileLinked, .fileSetType,
             .fileSetComment, .fileSetExecutable, .fileSetPermissions, .fileSetLabel,
             .fileDeleted, .fileCreatedDirectory, .fileSearched, .filePreviewedFile:
            return .files
        case .accountChangedPassword, .accountListedUsers, .accountListedGroups, .accountReadUser,
             .accountReadGroup, .accountCreatedUser, .accountCreatedGroup, .accountEditedUser,
             .accountEditedGroup, .accountDeletedUser, .accountDeletedGroup:
            return .accounts
        case .messageSent, .messageBroadcasted:
            return .messages
        case .boardGotBoards, .boardGotThreads, .boardGotThread, .boardAddedBoard,
             .boardRenamedBoard, .boardMovedBoard, .boardDeletedBoard, .boardGotBoardInfo,
             .boardSetBoardInfo, .boardAddedThread, .boardEditedThread, .boardMovedThread,
             .boardDeletedThread, .boardAddedPost, .boardEditedPost, .boardDeletedPost,
             .boardSearched:
            return .boards
        case .transferStartedFileDownload, .transferStoppedFileDownload, .transferCompletedFileDownload:
            return .downloads
        case .transferStartedFileUpload, .transferStoppedFileUpload, .transferCompletedFileUpload,
             .transferCompletedDirectoryUpload:
            return .uploads
        case .logGotLog, .eventsGotEvents, .settingsGotSettings, .settingsSetSettings,
             .banlistGotBans, .banlistAddedBan, .banlistDeletedBan:
            return .administration
        case .trackerGotCategories, .trackerGotServers, .trackerRegisteredServer:
            return .tracker
        }
    }

    public func formattedMessage(parameters: [String]) -> String {
        switch self {
        case .userLoggedIn:
            if parameters.count >= 2 {
                return "Logged in using \"\(parameters[0])\" on \"\(parameters[1])\""
            }
            return "Logged in"
        case .userLoginFailed:
            return "Login failed"
        case .userLoggedOut:
            return "Logged out"
        case .userChangedNick:
            if parameters.count >= 2 {
                return "Changed nick from \"\(parameters[0])\" to \"\(parameters[1])\""
            }
            return "Changed nick"
        case .userGotInfo:
            if let first = parameters.first {
                return "Got info for \"\(first)\""
            }
            return "Got user info"
        case .userDisconnectedUser:
            if let first = parameters.first {
                return "Disconnected \"\(first)\""
            }
            return "Disconnected user"
        case .userBannedUser:
            if let first = parameters.first {
                return "Banned \"\(first)\""
            }
            return "Banned user"
        case .userGotUsers:
            return "Listed users"
        case .fileListedDirectory:
            return Self.singlePathMessage(parameters, verb: "Listed")
        case .fileGotInfo:
            return Self.singlePathMessage(parameters, verb: "Got info for")
        case .fileMoved:
            if parameters.count >= 2 {
                return "Moved \"\(parameters[0])\" to \"\(parameters[1])\""
            }
            return "Moved file"
        case .fileLinked:
            if parameters.count >= 2 {
                return "Linked \"\(parameters[0])\" to \"\(parameters[1])\""
            }
            return "Linked file"
        case .fileSetType:
            return Self.singlePathMessage(parameters, verb: "Changed type for")
        case .fileSetComment:
            return Self.singlePathMessage(parameters, verb: "Changed comment for")
        case .fileSetExecutable:
            return Self.singlePathMessage(parameters, verb: "Changed executable mode for")
        case .fileSetPermissions:
            return Self.singlePathMessage(parameters, verb: "Changed permissions for")
        case .fileSetLabel:
            return Self.singlePathMessage(parameters, verb: "Changed label for")
        case .fileDeleted:
            return Self.singlePathMessage(parameters, verb: "Deleted")
        case .fileCreatedDirectory:
            return Self.singlePathMessage(parameters, verb: "Created")
        case .fileSearched:
            if let first = parameters.first {
                return "Searched for \"\(first)\""
            }
            return "Searched files"
        case .filePreviewedFile:
            return Self.singlePathMessage(parameters, verb: "Previewed")
        case .accountChangedPassword:
            return "Changed password"
        case .accountListedUsers:
            return "Listed users"
        case .accountListedGroups:
            return "Listed groups"
        case .accountReadUser:
            return Self.singleNameMessage(parameters, verb: "Read user")
        case .accountReadGroup:
            return Self.singleNameMessage(parameters, verb: "Read group")
        case .accountCreatedUser:
            return Self.singleNameMessage(parameters, verb: "Created user")
        case .accountCreatedGroup:
            return Self.singleNameMessage(parameters, verb: "Created group")
        case .accountEditedUser:
            return Self.singleNameMessage(parameters, verb: "Edited user")
        case .accountEditedGroup:
            return Self.singleNameMessage(parameters, verb: "Edited group")
        case .accountDeletedUser:
            return Self.singleNameMessage(parameters, verb: "Deleted user")
        case .accountDeletedGroup:
            return Self.singleNameMessage(parameters, verb: "Deleted group")
        case .messageSent:
            if let first = parameters.first {
                return "Sent message to \"\(first)\""
            }
            return "Sent direct message"
        case .messageBroadcasted:
            return "Sent broadcast"
        case .boardGotBoards:
            return "Got boards"
        case .boardGotThreads:
            return "Got threads"
        case .boardGotThread:
            if parameters.count >= 2 {
                return "Read thread \"\(parameters[0])\" in board \"\(parameters[1])\""
            }
            return "Read thread"
        case .boardAddedBoard:
            return Self.singleBoardMessage(parameters, verb: "Added")
        case .boardRenamedBoard:
            if parameters.count >= 2 {
                return "Renamed \"\(parameters[0])\" to \"\(parameters[1])\""
            }
            return "Renamed board"
        case .boardMovedBoard:
            if parameters.count >= 2 {
                return "Moved \"\(parameters[0])\" to \"\(parameters[1])\""
            }
            return "Moved board"
        case .boardDeletedBoard:
            return Self.singleBoardMessage(parameters, verb: "Deleted")
        case .boardGotBoardInfo:
            return Self.singleBoardMessage(parameters, verb: "Got board info for")
        case .boardSetBoardInfo:
            return Self.singleBoardMessage(parameters, verb: "Updated board info for")
        case .boardAddedThread:
            return Self.subjectBoardMessage(parameters, verb: "Added")
        case .boardEditedThread:
            return Self.subjectBoardMessage(parameters, verb: "Edited")
        case .boardMovedThread:
            if parameters.count >= 3 {
                return "Moved \"\(parameters[0])\" from \"\(parameters[1])\" to \"\(parameters[2])\""
            }
            return "Moved thread"
        case .boardDeletedThread:
            return Self.subjectBoardMessage(parameters, verb: "Deleted")
        case .boardAddedPost:
            return Self.subjectBoardMessage(parameters, verb: "Added")
        case .boardEditedPost:
            return Self.subjectBoardMessage(parameters, verb: "Edited")
        case .boardDeletedPost:
            return Self.subjectBoardMessage(parameters, verb: "Deleted")
        case .boardSearched:
            if let first = parameters.first {
                return "Searched boards for \"\(first)\""
            }
            return "Searched boards"
        case .transferStartedFileDownload:
            return Self.singlePathMessage(parameters, verb: "Started download of")
        case .transferStoppedFileDownload:
            return Self.pathSizeMessage(parameters, verb: "Stopped download of", preposition: "after sending")
        case .transferCompletedFileDownload:
            return Self.pathSizeMessage(parameters, verb: "Completed download of", preposition: "after sending")
        case .transferStartedFileUpload:
            return Self.singlePathMessage(parameters, verb: "Started upload of")
        case .transferStoppedFileUpload:
            return Self.pathSizeMessage(parameters, verb: "Stopped upload of", preposition: "after sending")
        case .transferCompletedFileUpload:
            return Self.pathSizeMessage(parameters, verb: "Completed upload of", preposition: "after sending")
        case .transferCompletedDirectoryUpload:
            return Self.singlePathMessage(parameters, verb: "Completed upload of")
        case .logGotLog:
            return "Got log"
        case .eventsGotEvents:
            return "Got events"
        case .settingsGotSettings:
            return "Got settings"
        case .settingsSetSettings:
            return "Saved settings"
        case .banlistGotBans:
            return "Got ban list"
        case .banlistAddedBan:
            return Self.singleNameMessage(parameters, verb: "Added ban of")
        case .banlistDeletedBan:
            return Self.singleNameMessage(parameters, verb: "Deleted ban of")
        case .trackerGotCategories:
            return "Got tracker categories"
        case .trackerGotServers:
            return "Got tracker servers"
        case .trackerRegisteredServer:
            return Self.singleNameMessage(parameters, verb: "Registered server")
        }
    }

    private static func singlePathMessage(_ parameters: [String], verb: String) -> String {
        if let first = parameters.first {
            return "\(verb) \"\(first)\""
        }
        return verb
    }

    private static func singleNameMessage(_ parameters: [String], verb: String) -> String {
        if let first = parameters.first {
            return "\(verb) \"\(first)\""
        }
        return verb
    }

    private static func singleBoardMessage(_ parameters: [String], verb: String) -> String {
        if let first = parameters.first {
            return "\(verb) \"\(first)\""
        }
        return verb
    }

    private static func subjectBoardMessage(_ parameters: [String], verb: String) -> String {
        if parameters.count >= 2 {
            return "\(verb) \"\(parameters[0])\" in \"\(parameters[1])\""
        }
        return verb
    }

    private static func pathSizeMessage(_ parameters: [String], verb: String, preposition: String) -> String {
        if parameters.count >= 2 {
            let size = parameters[1]
            let byteCount = Int64(size) ?? 0
            let formattedSize = ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
            return "\(verb) \"\(parameters[0])\" \(preposition) \(formattedSize)"
        }
        return verb
    }
}

public struct WiredServerEventRecord: Identifiable, Hashable, Sendable {
    public let eventCode: UInt32
    public let time: Date
    public let parameters: [String]
    public let nick: String
    public let login: String
    public let ip: String

    public init(
        eventCode: UInt32,
        time: Date,
        parameters: [String],
        nick: String,
        login: String,
        ip: String
    ) {
        self.eventCode = eventCode
        self.time = time
        self.parameters = parameters
        self.nick = nick
        self.login = login
        self.ip = ip
    }

    public init?(message: P7Message) {
        guard
            let eventCode = message.enumeration(forField: "wired.event.event"),
            let time = message.date(forField: "wired.event.time"),
            let nick = message.string(forField: "wired.user.nick"),
            let login = message.string(forField: "wired.user.login"),
            let ip = message.string(forField: "wired.user.ip")
        else {
            return nil
        }

        let parameters = (message.list(forField: "wired.event.parameters") as? [String]) ?? []
        self.init(
            eventCode: eventCode,
            time: time,
            parameters: parameters,
            nick: nick,
            login: login,
            ip: ip
        )
    }

    public var id: String {
        let joinedParameters = parameters.joined(separator: "\u{1F}")
        return "\(eventCode)|\(time.timeIntervalSince1970)|\(nick)|\(login)|\(ip)|\(joinedParameters)"
    }

    public var event: WiredServerEvent? {
        WiredServerEvent(rawValue: eventCode)
    }

    public var category: WiredServerEventCategory {
        event?.category ?? .administration
    }

    public var protocolName: String {
        event?.protocolName ?? "wired.event.unknown.\(eventCode)"
    }

    public var messageText: String {
        event?.formattedMessage(parameters: parameters)
            ?? [protocolName, parameters.joined(separator: ", ")]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
    }
}
