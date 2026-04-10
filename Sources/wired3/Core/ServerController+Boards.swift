//
//  ServerController+Boards.swift
//  wired3
//
//  Handles all wired.board.* messages: boards, threads, posts and
//  emoji reactions. Also contains the broadcast helpers that push
//  change notifications to subscribed clients.
//

// swiftlint:disable file_length
import Foundation
import WiredSwift

extension ServerController {

    // MARK: - Board listing

    func receiveBoardGetBoards(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard user.hasPrivilege(name: "wired.account.board.read_boards") else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        let username = user.username ?? ""
        let groupName = user.group ?? ""
        let boards = App.boardsController.getBoards(forUser: username, group: groupName)

        for board in boards {
            let reply = P7Message(withName: "wired.board.board_list", spec: self.spec)
            reply.addParameter(field: "wired.board.board", value: board.path)
            reply.addParameter(field: "wired.board.readable", value: board.canRead(user: username, group: groupName))
            reply.addParameter(field: "wired.board.writable", value: board.canWrite(user: username, group: groupName))
            self.reply(client: client, reply: reply, message: message)
        }

        let done = P7Message(withName: "wired.board.board_list.done", spec: self.spec)
        self.reply(client: client, reply: done, message: message)
        self.recordEvent(.boardGotBoards, client: client)
    }

    func receiveBoardGetThreads(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard user.hasPrivilege(name: "wired.account.board.read_boards") else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        let username = user.username ?? ""
        let groupName = user.group ?? ""

        let threads: [Thread]
        if let boardPath = message.string(forField: "wired.board.board"), !boardPath.isEmpty {
            guard let board = App.boardsController.getBoardInfo(path: boardPath) else {
                App.serverController.replyError(client: client, error: "wired.error.board_not_found", message: message)
                return
            }

            guard board.canRead(user: username, group: groupName) else {
                App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                return
            }

            threads = App.boardsController.getThreads(forBoard: boardPath)
        } else {
            threads = App.boardsController
                .getBoards(forUser: username, group: groupName)
                .flatMap { App.boardsController.getThreads(forBoard: $0.path) }
        }

        for thread in threads {
            let reply = P7Message(withName: "wired.board.thread_list", spec: self.spec)
            reply.addParameter(field: "wired.board.board", value: thread.board)
            reply.addParameter(field: "wired.board.thread", value: thread.uuid)
            reply.addParameter(field: "wired.board.post_date", value: thread.postDate)
            reply.addParameter(field: "wired.board.own_thread", value: thread.login == username)
            reply.addParameter(field: "wired.board.replies", value: UInt32(thread.replies))
            reply.addParameter(field: "wired.board.subject", value: thread.subject)
            reply.addParameter(field: "wired.user.nick", value: thread.nick)
            if let editDate = thread.editDate {
                reply.addParameter(field: "wired.board.edit_date", value: editDate)
            }
            if let latestReply = thread.latestReplyUUID {
                reply.addParameter(field: "wired.board.latest_reply", value: latestReply)
            }
            if let latestReplyDate = thread.latestReplyDate {
                reply.addParameter(field: "wired.board.latest_reply_date", value: latestReplyDate)
            }
            let emojiSummary = App.boardsController.getThreadReactionEmojis(threadUUID: thread.uuid)
            if !emojiSummary.isEmpty {
                reply.addParameter(field: "wired.board.reaction.emojis", value: emojiSummary)
            }
            self.reply(client: client, reply: reply, message: message)
        }

        let done = P7Message(withName: "wired.board.thread_list.done", spec: self.spec)
        self.reply(client: client, reply: done, message: message)
        self.recordEvent(.boardGotThreads, client: client)
    }

    func receiveBoardGetThread(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard user.hasPrivilege(name: "wired.account.board.read_boards") else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let threadID = message.uuid(forField: "wired.board.thread"), !threadID.isEmpty else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let thread = App.boardsController.getThread(uuid: threadID) else {
            App.serverController.replyError(client: client, error: "wired.error.thread_not_found", message: message)
            return
        }

        guard let board = App.boardsController.getBoardInfo(path: thread.board) else {
            App.serverController.replyError(client: client, error: "wired.error.board_not_found", message: message)
            return
        }

        let username = user.username ?? ""
        let groupName = user.group ?? ""
        guard board.canRead(user: username, group: groupName) else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        let threadReply = P7Message(withName: "wired.board.thread", spec: self.spec)
        threadReply.addParameter(field: "wired.board.thread", value: thread.uuid)
        threadReply.addParameter(field: "wired.board.text", value: thread.text)
        threadReply.addParameter(field: "wired.user.icon", value: thread.icon ?? Data())
        addAttachmentDescriptors(App.attachmentsController.descriptorsForBoardThread(thread.uuid), to: threadReply)
        self.reply(client: client, reply: threadReply, message: message)

        let posts = App.boardsController.getPosts(forThread: thread.uuid)
        for post in posts {
            let postReply = P7Message(withName: "wired.board.post_list", spec: self.spec)
            postReply.addParameter(field: "wired.board.thread", value: post.thread)
            postReply.addParameter(field: "wired.board.post", value: post.uuid)
            postReply.addParameter(field: "wired.board.post_date", value: post.postDate)
            postReply.addParameter(field: "wired.board.own_post", value: post.login == username)
            postReply.addParameter(field: "wired.board.text", value: post.text)
            postReply.addParameter(field: "wired.user.nick", value: post.nick)
            postReply.addParameter(field: "wired.user.icon", value: post.icon ?? Data())
            addAttachmentDescriptors(App.attachmentsController.descriptorsForBoardPost(post.uuid), to: postReply)
            if let editDate = post.editDate {
                postReply.addParameter(field: "wired.board.edit_date", value: editDate)
            }
            self.reply(client: client, reply: postReply, message: message)
        }

        let done = P7Message(withName: "wired.board.post_list.done", spec: self.spec)
        done.addParameter(field: "wired.board.thread", value: thread.uuid)
        self.reply(client: client, reply: done, message: message)
        self.recordEvent(.boardGotThread, client: client, parameters: [thread.subject, thread.board])
    }

    func receiveBoardSearch(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard
            user.hasPrivilege(name: "wired.account.board.read_boards"),
            user.hasPrivilege(name: "wired.account.board.search_boards")
        else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let query = message.string(forField: "wired.board.query") else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let done = P7Message(withName: "wired.board.search_list.done", spec: self.spec)
            self.reply(client: client, reply: done, message: message)
            return
        }

        let username = user.username ?? ""
        let groupName = user.group ?? ""
        let readableBoardPaths = Set(
            App.boardsController
                .getBoards(forUser: username, group: groupName)
                .map(\.path)
        )

        let scopedBoardPaths: [String]
        if let scopedBoardPath = message.string(forField: "wired.board.board"), !scopedBoardPath.isEmpty {
            guard let board = App.boardsController.getBoardInfo(path: scopedBoardPath) else {
                App.serverController.replyError(client: client, error: "wired.error.board_not_found", message: message)
                return
            }

            guard board.canRead(user: username, group: groupName) else {
                App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                return
            }

            scopedBoardPaths = readableBoardPaths
                .filter { $0 == scopedBoardPath || $0.hasPrefix(scopedBoardPath + "/") }
                .sorted()
        } else {
            scopedBoardPaths = readableBoardPaths.sorted()
        }

        guard !scopedBoardPaths.isEmpty else {
            let done = P7Message(withName: "wired.board.search_list.done", spec: self.spec)
            self.reply(client: client, reply: done, message: message)
            return
        }

        do {
            let results = try App.boardsController.search(query: trimmed, boardPaths: scopedBoardPaths, limit: 100)
            for result in results {
                let reply = P7Message(withName: "wired.board.search_list", spec: self.spec)
                reply.addParameter(field: "wired.board.board", value: result.boardPath)
                reply.addParameter(field: "wired.board.thread", value: result.threadUUID)
                reply.addParameter(field: "wired.board.subject", value: result.subject)
                reply.addParameter(field: "wired.user.nick", value: result.nick)
                reply.addParameter(field: "wired.board.post_date", value: result.postDate)
                reply.addParameter(field: "wired.board.snippet", value: result.snippet)
                if let postUUID = result.postUUID {
                    reply.addParameter(field: "wired.board.post", value: postUUID)
                }
                if let editDate = result.editDate {
                    reply.addParameter(field: "wired.board.edit_date", value: editDate)
                }
                self.reply(client: client, reply: reply, message: message)
            }

            let done = P7Message(withName: "wired.board.search_list.done", spec: self.spec)
            self.reply(client: client, reply: done, message: message)
            self.recordEvent(.boardSearched, client: client, parameters: [trimmed])
        } catch {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
        }
    }

    // MARK: - Board CRUD

    func receiveBoardAddBoard(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard user.hasPrivilege(name: "wired.account.board.add_boards") else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard
            let path = message.string(forField: "wired.board.board")?.trimmingCharacters(in: .whitespacesAndNewlines),
            !path.isEmpty,
            let owner = message.string(forField: "wired.board.owner"),
            let ownerRead = message.bool(forField: "wired.board.owner.read"),
            let ownerWrite = message.bool(forField: "wired.board.owner.write"),
            let group = message.string(forField: "wired.board.group"),
            let groupRead = message.bool(forField: "wired.board.group.read"),
            let groupWrite = message.bool(forField: "wired.board.group.write"),
            let everyoneRead = message.bool(forField: "wired.board.everyone.read"),
            let everyoneWrite = message.bool(forField: "wired.board.everyone.write")
        else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        let parentPath = (path as NSString).deletingLastPathComponent
        if !parentPath.isEmpty && parentPath != "." {
            guard App.boardsController.getBoardInfo(path: parentPath) != nil else {
                App.serverController.replyError(client: client, error: "wired.error.board_not_found", message: message)
                return
            }
        }

        guard let board = App.boardsController.addBoard(
            path: path,
            owner: owner,
            group: group,
            ownerRead: ownerRead,
            ownerWrite: ownerWrite,
            groupRead: groupRead,
            groupWrite: groupWrite,
            everyoneRead: everyoneRead,
            everyoneWrite: everyoneWrite
        ) else {
            App.serverController.replyError(client: client, error: "wired.error.board_exists", message: message)
            return
        }

        App.serverController.replyOK(client: client, message: message)
        broadcastBoardAdded(board: board)
        self.recordEvent(.boardAddedBoard, client: client, parameters: [board.path])
    }

    func receiveBoardDeleteBoard(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard user.hasPrivilege(name: "wired.account.board.delete_boards") else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let path = message.string(forField: "wired.board.board"), !path.isEmpty else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard App.boardsController.getBoardInfo(path: path) != nil else {
            App.serverController.replyError(client: client, error: "wired.error.board_not_found", message: message)
            return
        }

        guard App.boardsController.deleteBoard(path: path) else {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        App.serverController.replyOK(client: client, message: message)
        broadcastBoardDeleted(path: path)
        self.recordEvent(.boardDeletedBoard, client: client, parameters: [path])
    }

    func receiveBoardRenameBoard(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard user.hasPrivilege(name: "wired.account.board.rename_boards") else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard
            let path = message.string(forField: "wired.board.board"),
            let newPath = message.string(forField: "wired.board.new_board"),
            !path.isEmpty,
            !newPath.isEmpty
        else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard App.boardsController.getBoardInfo(path: path) != nil else {
            App.serverController.replyError(client: client, error: "wired.error.board_not_found", message: message)
            return
        }

        if App.boardsController.getBoardInfo(path: newPath) != nil {
            App.serverController.replyError(client: client, error: "wired.error.board_exists", message: message)
            return
        }

        guard App.boardsController.renameBoard(path: path, newPath: newPath) else {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        App.serverController.replyOK(client: client, message: message)
        broadcastBoardRenamed(path: path, newPath: newPath)
        self.recordEvent(.boardRenamedBoard, client: client, parameters: [path, newPath])
    }

    func receiveBoardMoveBoard(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard user.hasPrivilege(name: "wired.account.board.move_boards") else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard
            let path = message.string(forField: "wired.board.board"),
            let newPath = message.string(forField: "wired.board.new_board"),
            !path.isEmpty,
            !newPath.isEmpty
        else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard App.boardsController.getBoardInfo(path: path) != nil else {
            App.serverController.replyError(client: client, error: "wired.error.board_not_found", message: message)
            return
        }

        if App.boardsController.getBoardInfo(path: newPath) != nil {
            App.serverController.replyError(client: client, error: "wired.error.board_exists", message: message)
            return
        }

        guard App.boardsController.moveBoard(path: path, newPath: newPath) else {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        App.serverController.replyOK(client: client, message: message)
        broadcastBoardMoved(path: path, newPath: newPath)
        self.recordEvent(.boardMovedBoard, client: client, parameters: [path, newPath])
    }

    func receiveBoardGetBoardInfo(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard user.hasPrivilege(name: "wired.account.board.get_board_info") else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let path = message.string(forField: "wired.board.board"), !path.isEmpty else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let board = App.boardsController.getBoardInfo(path: path) else {
            App.serverController.replyError(client: client, error: "wired.error.board_not_found", message: message)
            return
        }

        let reply = P7Message(withName: "wired.board.board_info", spec: self.spec)
        reply.addParameter(field: "wired.board.board", value: board.path)
        reply.addParameter(field: "wired.board.owner", value: board.owner)
        reply.addParameter(field: "wired.board.owner.read", value: board.ownerRead)
        reply.addParameter(field: "wired.board.owner.write", value: board.ownerWrite)
        reply.addParameter(field: "wired.board.group", value: board.group)
        reply.addParameter(field: "wired.board.group.read", value: board.groupRead)
        reply.addParameter(field: "wired.board.group.write", value: board.groupWrite)
        reply.addParameter(field: "wired.board.everyone.read", value: board.everyoneRead)
        reply.addParameter(field: "wired.board.everyone.write", value: board.everyoneWrite)
        self.reply(client: client, reply: reply, message: message)
        self.recordEvent(.boardGotBoardInfo, client: client, parameters: [board.path])
    }

    func receiveBoardSetBoardInfo(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard user.hasPrivilege(name: "wired.account.board.set_board_info") else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard
            let path = message.string(forField: "wired.board.board"),
            !path.isEmpty,
            let owner = message.string(forField: "wired.board.owner"),
            let ownerRead = message.bool(forField: "wired.board.owner.read"),
            let ownerWrite = message.bool(forField: "wired.board.owner.write"),
            let group = message.string(forField: "wired.board.group"),
            let groupRead = message.bool(forField: "wired.board.group.read"),
            let groupWrite = message.bool(forField: "wired.board.group.write"),
            let everyoneRead = message.bool(forField: "wired.board.everyone.read"),
            let everyoneWrite = message.bool(forField: "wired.board.everyone.write")
        else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard App.boardsController.getBoardInfo(path: path) != nil else {
            App.serverController.replyError(client: client, error: "wired.error.board_not_found", message: message)
            return
        }

        guard App.boardsController.setBoardInfo(
            path: path,
            owner: owner,
            group: group,
            ownerRead: ownerRead,
            ownerWrite: ownerWrite,
            groupRead: groupRead,
            groupWrite: groupWrite,
            everyoneRead: everyoneRead,
            everyoneWrite: everyoneWrite
        ) else {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        App.serverController.replyOK(client: client, message: message)
        if let board = App.boardsController.getBoardInfo(path: path) {
            broadcastBoardInfoChanged(board: board)
        }
        self.recordEvent(.boardSetBoardInfo, client: client, parameters: [path])
    }

    // MARK: - Thread CRUD

    func receiveBoardAddThread(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard user.hasPrivilege(name: "wired.account.board.add_threads") else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard
            let boardPath = message.string(forField: "wired.board.board"),
            let subject = message.string(forField: "wired.board.subject"),
            let text = message.string(forField: "wired.board.text"),
            !boardPath.isEmpty
        else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let board = App.boardsController.getBoardInfo(path: boardPath) else {
            App.serverController.replyError(client: client, error: "wired.error.board_not_found", message: message)
            return
        }

        let username = user.username ?? ""
        let groupName = user.group ?? ""
        guard board.canWrite(user: username, group: groupName) else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        let attachmentIDs = App.attachmentsController.attachmentIDsFromMessage(message) ?? []
        let descriptors = App.attachmentsController.descriptorsForMessageAttachmentIDs(
            attachmentIDs,
            client: client,
            boardPath: boardPath
        )
        guard attachmentIDs.isEmpty || descriptors != nil else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let thread = App.boardsController.addThread(
            board: boardPath,
            subject: subject,
            text: text,
            nick: client.nick ?? username,
            login: username,
            icon: client.icon
        ) else {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        guard attachmentIDs.isEmpty || App.attachmentsController.linkBoardThreadAttachments(
            ids: attachmentIDs,
            boardPath: boardPath,
            threadUUID: thread.uuid,
            ownerLogin: username
        ) else {
            _ = App.boardsController.deleteThread(uuid: thread.uuid)
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        App.serverController.replyOK(client: client, message: message)
        broadcastThreadAdded(thread: thread)
        self.recordEvent(.boardAddedThread, client: client, parameters: [thread.subject, thread.board])
    }

    func receiveBoardEditThread(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard
            let uuid = message.uuid(forField: "wired.board.thread"),
            let subject = message.string(forField: "wired.board.subject"),
            let text = message.string(forField: "wired.board.text"),
            !uuid.isEmpty
        else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let existing = App.boardsController.getThread(uuid: uuid) else {
            App.serverController.replyError(client: client, error: "wired.error.thread_not_found", message: message)
            return
        }

        let username = user.username ?? ""
        let canEditOwn = user.hasPrivilege(name: "wired.account.board.edit_own_threads_and_posts")
        let canEditAll = user.hasPrivilege(name: "wired.account.board.edit_all_threads_and_posts")
        if !(canEditAll || (canEditOwn && existing.login == username)) {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        let attachmentIDs = App.attachmentsController.attachmentIDsFromMessage(message)
        if let attachmentIDs {
            let descriptors = App.attachmentsController.descriptorsForMessageAttachmentIDs(
                attachmentIDs,
                client: client,
                threadUUID: uuid
            )
            guard descriptors != nil else {
                App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
                return
            }
        }

        guard let thread = App.boardsController.editThread(uuid: uuid, subject: subject, text: text) else {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        if let attachmentIDs,
           !App.attachmentsController.linkBoardThreadAttachments(
               ids: attachmentIDs,
               boardPath: thread.board,
               threadUUID: uuid,
               ownerLogin: username
           ) {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        App.serverController.replyOK(client: client, message: message)
        broadcastThreadChanged(thread: thread)
        self.recordEvent(.boardEditedThread, client: client, parameters: [thread.subject, thread.board])
    }

    func receiveBoardMoveThread(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard user.hasPrivilege(name: "wired.account.board.move_threads") else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard
            let uuid = message.uuid(forField: "wired.board.thread"),
            let newBoard = message.string(forField: "wired.board.new_board"),
            !uuid.isEmpty,
            !newBoard.isEmpty
        else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard App.boardsController.getThread(uuid: uuid) != nil else {
            App.serverController.replyError(client: client, error: "wired.error.thread_not_found", message: message)
            return
        }

        guard App.boardsController.getBoardInfo(path: newBoard) != nil else {
            App.serverController.replyError(client: client, error: "wired.error.board_not_found", message: message)
            return
        }

        guard let existingThread = App.boardsController.getThread(uuid: uuid) else {
            App.serverController.replyError(client: client, error: "wired.error.thread_not_found", message: message)
            return
        }

        guard let thread = App.boardsController.moveThread(uuid: uuid, toBoard: newBoard) else {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        App.serverController.replyOK(client: client, message: message)
        broadcastThreadMoved(thread: thread)
        self.recordEvent(.boardMovedThread, client: client, parameters: [thread.subject, existingThread.board, newBoard])
    }

    func receiveBoardDeleteThread(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard let uuid = message.uuid(forField: "wired.board.thread"), !uuid.isEmpty else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let existing = App.boardsController.getThread(uuid: uuid) else {
            App.serverController.replyError(client: client, error: "wired.error.thread_not_found", message: message)
            return
        }

        let username = user.username ?? ""
        let canDeleteOwn = user.hasPrivilege(name: "wired.account.board.delete_own_threads_and_posts")
        let canDeleteAll = user.hasPrivilege(name: "wired.account.board.delete_all_threads_and_posts")
        if !(canDeleteAll || (canDeleteOwn && existing.login == username)) {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard App.boardsController.deleteThread(uuid: uuid) else {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        App.attachmentsController.deleteBoardAttachments(forThread: uuid)
        App.serverController.replyOK(client: client, message: message)
        broadcastThreadDeleted(uuid: uuid)
        self.recordEvent(.boardDeletedThread, client: client, parameters: [existing.subject, existing.board])
    }

    // MARK: - Post CRUD

    func receiveBoardAddPost(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard user.hasPrivilege(name: "wired.account.board.add_posts") else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard
            let threadUUID = message.uuid(forField: "wired.board.thread"),
            let text = message.string(forField: "wired.board.text"),
            !threadUUID.isEmpty
        else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let thread = App.boardsController.getThread(uuid: threadUUID) else {
            App.serverController.replyError(client: client, error: "wired.error.thread_not_found", message: message)
            return
        }

        guard let board = App.boardsController.getBoardInfo(path: thread.board) else {
            App.serverController.replyError(client: client, error: "wired.error.board_not_found", message: message)
            return
        }

        let username = user.username ?? ""
        let groupName = user.group ?? ""
        guard board.canWrite(user: username, group: groupName) else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        let attachmentIDs = App.attachmentsController.attachmentIDsFromMessage(message) ?? []
        let descriptors = App.attachmentsController.descriptorsForMessageAttachmentIDs(
            attachmentIDs,
            client: client,
            threadUUID: threadUUID
        )
        guard attachmentIDs.isEmpty || descriptors != nil else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let post = App.boardsController.addPost(
            threadUUID: threadUUID,
            text: text,
            nick: client.nick ?? username,
            login: username,
            icon: client.icon
        ),
        let updatedThread = App.boardsController.getThread(uuid: threadUUID) else {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        guard attachmentIDs.isEmpty || App.attachmentsController.linkBoardPostAttachments(
            ids: attachmentIDs,
            boardPath: updatedThread.board,
            threadUUID: threadUUID,
            postUUID: post.uuid,
            ownerLogin: username
        ) else {
            _ = App.boardsController.deletePost(uuid: post.uuid)
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        App.serverController.replyOK(client: client, message: message)
        broadcastThreadChanged(thread: updatedThread, appendedPost: post)
        self.recordEvent(.boardAddedPost, client: client, parameters: [updatedThread.subject, updatedThread.board])
    }

    func receiveBoardEditPost(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard
            let uuid = message.uuid(forField: "wired.board.post"),
            let text = message.string(forField: "wired.board.text"),
            !uuid.isEmpty
        else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let existing = App.boardsController.posts[uuid.lowercased()] else {
            App.serverController.replyError(client: client, error: "wired.error.post_not_found", message: message)
            return
        }
        let threadUUID = existing.thread

        let username = user.username ?? ""
        let canEditOwn = user.hasPrivilege(name: "wired.account.board.edit_own_threads_and_posts")
        let canEditAll = user.hasPrivilege(name: "wired.account.board.edit_all_threads_and_posts")
        if !(canEditAll || (canEditOwn && existing.login == username)) {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        let attachmentIDs = App.attachmentsController.attachmentIDsFromMessage(message)
        if let attachmentIDs {
            let descriptors = App.attachmentsController.descriptorsForMessageAttachmentIDs(
                attachmentIDs,
                client: client,
                postUUID: uuid
            )
            guard descriptors != nil else {
                App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
                return
            }
        }

        guard let editedPost = App.boardsController.editPost(uuid: uuid, text: text) else {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        if let attachmentIDs,
           let thread = App.boardsController.getThread(uuid: threadUUID),
           !App.attachmentsController.linkBoardPostAttachments(
               ids: attachmentIDs,
               boardPath: thread.board,
               threadUUID: threadUUID,
               postUUID: uuid,
               ownerLogin: username
           ) {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        App.serverController.replyOK(client: client, message: message)
        if let thread = App.boardsController.getThread(uuid: threadUUID) {
            broadcastThreadChanged(thread: thread, appendedPost: editedPost)
            self.recordEvent(.boardEditedPost, client: client, parameters: [thread.subject, thread.board])
        }
    }

    func receiveBoardDeletePost(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard let uuid = message.uuid(forField: "wired.board.post"), !uuid.isEmpty else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let existing = App.boardsController.posts[uuid.lowercased()] else {
            App.serverController.replyError(client: client, error: "wired.error.post_not_found", message: message)
            return
        }

        let username = user.username ?? ""
        let canDeleteOwn = user.hasPrivilege(name: "wired.account.board.delete_own_threads_and_posts")
        let canDeleteAll = user.hasPrivilege(name: "wired.account.board.delete_all_threads_and_posts")
        if !(canDeleteAll || (canDeleteOwn && existing.login == username)) {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        let threadUUID = existing.thread
        guard App.boardsController.deletePost(uuid: uuid) else {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        App.attachmentsController.deleteBoardAttachments(forPost: uuid)
        App.serverController.replyOK(client: client, message: message)
        if let thread = App.boardsController.getThread(uuid: threadUUID) {
            broadcastThreadChanged(thread: thread)
            self.recordEvent(.boardDeletedPost, client: client, parameters: [thread.subject, thread.board])
        }
    }

    // MARK: - Board subscriptions

    func receiveBoardSubscribeBoards(client: Client, message: P7Message) {
        guard let user = client.user else { return }

        if !user.hasPrivilege(name: "wired.account.board.read_boards") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        if client.isSubscribedToBoards {
            App.serverController.replyError(client: client, error: "wired.error.already_subscribed", message: message)
            return
        }

        client.isSubscribedToBoards = true
        App.serverController.replyOK(client: client, message: message)
    }

    func receiveBoardUnsubscribeBoards(client: Client, message: P7Message) {
        guard let user = client.user else { return }

        if !user.hasPrivilege(name: "wired.account.board.read_boards") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        if !client.isSubscribedToBoards {
            App.serverController.replyError(client: client, error: "wired.error.not_subscribed", message: message)
            return
        }

        client.isSubscribedToBoards = false
        App.serverController.replyOK(client: client, message: message)
    }

    // MARK: - Reaction handlers

    func receiveBoardGetReactions(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }
        guard user.hasPrivilege(name: "wired.account.board.read_boards") else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let threadUUID = message.uuid(forField: "wired.board.thread"), !threadUUID.isEmpty else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }
        let postUUID = message.uuid(forField: "wired.board.post")

        guard let thread = App.boardsController.getThread(uuid: threadUUID),
              let board = App.boardsController.getBoardInfo(path: thread.board) else {
            App.serverController.replyError(client: client, error: "wired.error.thread_not_found", message: message)
            return
        }
        let username = user.username ?? ""
        guard board.canRead(user: username, group: user.group ?? "") else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        let summaries = App.boardsController.getReactions(threadUUID: threadUUID,
                                                          postUUID: postUUID,
                                                          currentLogin: username)
        for summary in summaries {
            let reply = P7Message(withName: "wired.board.reaction_list", spec: self.spec)
            reply.addParameter(field: "wired.board.thread", value: threadUUID)
            if let postUUID {
                reply.addParameter(field: "wired.board.post", value: postUUID)
            }
            reply.addParameter(field: "wired.board.reaction.emoji", value: summary.emoji)
            reply.addParameter(field: "wired.board.reaction.count", value: UInt32(summary.count))
            reply.addParameter(field: "wired.board.reaction.is_own", value: summary.isOwn)
            if !summary.nicks.isEmpty {
                reply.addParameter(field: "wired.board.reaction.nicks", value: summary.nicks.joined(separator: "|"))
            }
            self.reply(client: client, reply: reply, message: message)
        }
        App.serverController.replyOK(client: client, message: message)
    }

    func receiveBoardAddReaction(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }
        guard user.hasPrivilege(name: "wired.account.board.add_reactions") else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard
            let threadUUID = message.uuid(forField: "wired.board.thread"), !threadUUID.isEmpty,
            let emoji = message.string(forField: "wired.board.reaction.emoji"), !emoji.isEmpty
        else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }
        let postUUID = message.uuid(forField: "wired.board.post")

        guard let thread = App.boardsController.getThread(uuid: threadUUID),
              let board = App.boardsController.getBoardInfo(path: thread.board) else {
            App.serverController.replyError(client: client, error: "wired.error.thread_not_found", message: message)
            return
        }
        let username  = user.username ?? ""
        let groupName = user.group ?? ""
        guard board.canRead(user: username, group: groupName) else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        let nick = client.nick ?? username
        guard let result = App.boardsController.toggleReaction(
            threadUUID: threadUUID, postUUID: postUUID,
            emoji: emoji, login: username, nick: nick
        ) else {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        App.serverController.replyOK(client: client, message: message)

        if let oldEmoji = result.replacedEmoji {
            broadcastReactionChanged(board: board.path, threadUUID: threadUUID, postUUID: postUUID,
                                     emoji: oldEmoji, count: result.replacedCount, nick: nick, added: false)
        }
        broadcastReactionChanged(board: board.path, threadUUID: threadUUID, postUUID: postUUID,
                                 emoji: emoji, count: result.count, nick: nick, added: result.added)
    }

    // MARK: - Broadcast helpers

    private func broadcastReactionChanged(board: String, threadUUID: String, postUUID: String?,
                                          emoji: String, count: Int, nick: String, added: Bool) {
        let messageName = added ? "wired.board.reaction_added" : "wired.board.reaction_removed"
        forEachBoardSubscriber { connectedClient, connectedUser in
            let username  = connectedUser.username ?? ""
            let groupName = connectedUser.group ?? ""
            guard let boardInfo = App.boardsController.getBoardInfo(path: board),
                  boardInfo.canRead(user: username, group: groupName) else { return }

            let broadcast = P7Message(withName: messageName, spec: self.spec)
            broadcast.addParameter(field: "wired.board.board", value: board)
            broadcast.addParameter(field: "wired.board.thread", value: threadUUID)
            if let postUUID {
                broadcast.addParameter(field: "wired.board.post", value: postUUID)
            }
            broadcast.addParameter(field: "wired.board.reaction.emoji", value: emoji)
            broadcast.addParameter(field: "wired.board.reaction.count", value: UInt32(count))
            if added {
                broadcast.addParameter(field: "wired.board.reaction.nick", value: nick)
            }
            _ = self.send(message: broadcast, client: connectedClient)
        }
    }

    private func broadcastBoardAdded(board: Board) {
        forEachBoardSubscriber { connectedClient, connectedUser in
            let username = connectedUser.username ?? ""
            let groupName = connectedUser.group ?? ""
            let readable = board.canRead(user: username, group: groupName)
            let writable = board.canWrite(user: username, group: groupName)

            let broadcast = P7Message(withName: "wired.board.board_added", spec: self.spec)
            broadcast.addParameter(field: "wired.board.board", value: board.path)
            broadcast.addParameter(field: "wired.board.readable", value: readable)
            broadcast.addParameter(field: "wired.board.writable", value: writable)
            _ = self.send(message: broadcast, client: connectedClient)
        }
    }

    private func broadcastBoardDeleted(path: String) {
        forEachBoardSubscriber { connectedClient, _ in
            let broadcast = P7Message(withName: "wired.board.board_deleted", spec: self.spec)
            broadcast.addParameter(field: "wired.board.board", value: path)
            _ = self.send(message: broadcast, client: connectedClient)
        }
    }

    private func broadcastBoardRenamed(path: String, newPath: String) {
        forEachBoardSubscriber { connectedClient, _ in
            let broadcast = P7Message(withName: "wired.board.board_renamed", spec: self.spec)
            broadcast.addParameter(field: "wired.board.board", value: path)
            broadcast.addParameter(field: "wired.board.new_board", value: newPath)
            _ = self.send(message: broadcast, client: connectedClient)
        }
    }

    private func broadcastBoardMoved(path: String, newPath: String) {
        forEachBoardSubscriber { connectedClient, _ in
            let broadcast = P7Message(withName: "wired.board.board_moved", spec: self.spec)
            broadcast.addParameter(field: "wired.board.board", value: path)
            broadcast.addParameter(field: "wired.board.new_board", value: newPath)
            _ = self.send(message: broadcast, client: connectedClient)
        }
    }

    private func broadcastBoardInfoChanged(board: Board) {
        forEachBoardSubscriber { connectedClient, connectedUser in
            let username = connectedUser.username ?? ""
            let groupName = connectedUser.group ?? ""
            let broadcast = P7Message(withName: "wired.board.board_info_changed", spec: self.spec)
            broadcast.addParameter(field: "wired.board.board", value: board.path)
            broadcast.addParameter(field: "wired.board.readable", value: board.canRead(user: username, group: groupName))
            broadcast.addParameter(field: "wired.board.writable", value: board.canWrite(user: username, group: groupName))
            _ = self.send(message: broadcast, client: connectedClient)
        }
    }

    private func broadcastThreadAdded(thread: Thread) {
        forEachBoardSubscriber { connectedClient, connectedUser in
            let username = connectedUser.username ?? ""
            let groupName = connectedUser.group ?? ""
            guard let board = App.boardsController.getBoardInfo(path: thread.board),
                  board.canRead(user: username, group: groupName) else { return }

            let broadcast = P7Message(withName: "wired.board.thread_added", spec: self.spec)
            broadcast.addParameter(field: "wired.board.board", value: thread.board)
            broadcast.addParameter(field: "wired.board.thread", value: thread.uuid)
            broadcast.addParameter(field: "wired.board.post_date", value: thread.postDate)
            broadcast.addParameter(field: "wired.board.own_thread", value: thread.login == username)
            broadcast.addParameter(field: "wired.board.replies", value: UInt32(thread.replies))
            broadcast.addParameter(field: "wired.board.subject", value: thread.subject)
            broadcast.addParameter(field: "wired.user.nick", value: thread.nick)
            broadcast.addParameter(field: "wired.user.icon", value: thread.icon ?? Data())
            addAttachmentDescriptors(App.attachmentsController.descriptorsForBoardThread(thread.uuid), to: broadcast)
            _ = self.send(message: broadcast, client: connectedClient)
        }
    }

    private func broadcastThreadChanged(thread: Thread, appendedPost: Post? = nil) {
        forEachBoardSubscriber { connectedClient, connectedUser in
            let username = connectedUser.username ?? ""
            let groupName = connectedUser.group ?? ""
            guard let board = App.boardsController.getBoardInfo(path: thread.board),
                  board.canRead(user: username, group: groupName) else { return }

            let broadcast = P7Message(withName: "wired.board.thread_changed", spec: self.spec)
            broadcast.addParameter(field: "wired.board.board", value: thread.board)
            broadcast.addParameter(field: "wired.board.thread", value: thread.uuid)
            broadcast.addParameter(field: "wired.board.subject", value: thread.subject)
            broadcast.addParameter(field: "wired.board.replies", value: UInt32(thread.replies))
            if let editDate = thread.editDate {
                broadcast.addParameter(field: "wired.board.edit_date", value: editDate)
            }
            if let latestReply = thread.latestReplyUUID {
                broadcast.addParameter(field: "wired.board.latest_reply", value: latestReply)
            }
            if let latestReplyDate = thread.latestReplyDate {
                broadcast.addParameter(field: "wired.board.latest_reply_date", value: latestReplyDate)
            }
            if let appendedPost {
                broadcast.addParameter(field: "wired.board.post", value: appendedPost.uuid)
                broadcast.addParameter(field: "wired.board.text", value: appendedPost.text)
                broadcast.addParameter(field: "wired.user.nick", value: appendedPost.nick)
                broadcast.addParameter(field: "wired.user.icon", value: appendedPost.icon ?? Data())
                broadcast.addParameter(field: "wired.board.post_date", value: appendedPost.postDate)
                broadcast.addParameter(field: "wired.board.own_post", value: appendedPost.login == username)
                addAttachmentDescriptors(App.attachmentsController.descriptorsForBoardPost(appendedPost.uuid), to: broadcast)
                if let editDate = appendedPost.editDate {
                    broadcast.addParameter(field: "wired.board.edit_date", value: editDate)
                }
            } else {
                addAttachmentDescriptors(App.attachmentsController.descriptorsForBoardThread(thread.uuid), to: broadcast)
            }
            _ = self.send(message: broadcast, client: connectedClient)
        }
    }

    private func addAttachmentDescriptors(_ descriptors: [AttachmentDescriptor], to message: P7Message) {
        guard !descriptors.isEmpty else { return }
        message.addParameter(field: "wired.attachment.descriptors", value: App.attachmentsController.descriptorStrings(descriptors))
    }

    private func broadcastThreadMoved(thread: Thread) {
        forEachBoardSubscriber { connectedClient, connectedUser in
            let username = connectedUser.username ?? ""
            let groupName = connectedUser.group ?? ""
            guard let board = App.boardsController.getBoardInfo(path: thread.board),
                  board.canRead(user: username, group: groupName) else { return }

            let broadcast = P7Message(withName: "wired.board.thread_moved", spec: self.spec)
            broadcast.addParameter(field: "wired.board.thread", value: thread.uuid)
            broadcast.addParameter(field: "wired.board.new_board", value: thread.board)
            _ = self.send(message: broadcast, client: connectedClient)
        }
    }

    private func broadcastThreadDeleted(uuid: String) {
        forEachBoardSubscriber { connectedClient, _ in
            let broadcast = P7Message(withName: "wired.board.thread_deleted", spec: self.spec)
            broadcast.addParameter(field: "wired.board.thread", value: uuid)
            _ = self.send(message: broadcast, client: connectedClient)
        }
    }

    private func forEachBoardSubscriber(_ body: (Client, User) -> Void) {
        for connectedClient in App.clientsController.connectedClientsSnapshot() {
            guard connectedClient.state == .LOGGED_IN else { continue }
            guard connectedClient.isSubscribedToBoards else { continue }
            guard let connectedUser = connectedClient.user else { continue }

            if !connectedUser.hasPrivilege(name: "wired.account.board.read_boards") {
                connectedClient.isSubscribedToBoards = false
                continue
            }
            body(connectedClient, connectedUser)
        }
    }
}
