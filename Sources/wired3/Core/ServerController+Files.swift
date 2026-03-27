//
//  ServerController+Files.swift
//  wired3
//
//  Handles wired.transfer.* messages: file downloads, file uploads
//  and directory uploads. File browsing (wired.file.*) is handled
//  by FilesController and routed via handleMessage.
//

import Foundation
import WiredSwift

extension ServerController {

    // MARK: - Downloads

    func receiveDownloadFile(_ client: Client, _ message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        if !user.hasPrivilege(name: "wired.account.transfer.download_files") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let path = message.string(forField: "wired.file.path") else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        if !File.isValid(path: path) {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }

        let normalizedPath = NSString(string: path).standardizingPath

        if let privilege = App.filesController.dropBoxPrivileges(forVirtualPath: normalizedPath) {
            if !user.hasPermission(toRead: privilege) {
                App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                return
            }
        }

        guard let dataOffset = message.uint64(forField: "wired.transfer.data_offset"),
              let rsrcOffset = message.uint64(forField: "wired.transfer.rsrc_offset") else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        if let transfer = App.transfersController.download(path: normalizedPath,
                                                           dataOffset: dataOffset,
                                                           rsrcOffset: rsrcOffset,
                                                           client: client, message: message) {
            client.transfer = transfer

            self.recordEvent(.transferStartedFileDownload, client: client, parameters: [normalizedPath])

            if App.transfersController.run(transfer: transfer, client: client, message: message) {
                self.recordEvent(
                    .transferCompletedFileDownload,
                    client: client,
                    parameters: [normalizedPath, String(transfer.actualTransferred ?? 0)]
                )
                client.state = .DISCONNECTED
            } else {
                self.recordEvent(
                    .transferStoppedFileDownload,
                    client: client,
                    parameters: [normalizedPath, String(transfer.actualTransferred ?? 0)]
                )
            }

            client.transfer = nil
        } else {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
        }
    }

    // MARK: - Uploads

    func receiveUploadFile(_ client: Client, _ message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard let path = message.string(forField: "wired.file.path") else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        if !File.isValid(path: path) {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }

        let normalizedPath = NSString(string: path).standardizingPath
        let realPath = App.filesController.real(path: normalizedPath)
        let parentPath = realPath.stringByDeletingLastPathComponent

        if let privilege = App.filesController.dropBoxPrivileges(forVirtualPath: normalizedPath) {
            if !user.hasPermission(toWrite: privilege) {
                App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                return
            }
        }

        if let type = File.FileType.type(path: parentPath) {
            switch type {
            case .uploads, .dropbox:
                if !user.hasPrivilege(name: "wired.account.transfer.upload_files") {
                    App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                    return
                }
            default:
                if !user.hasPrivilege(name: "wired.account.transfer.upload_anywhere") {
                    App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                    return
                }
            }
        } else {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }

        let dataSize = message.uint64(forField: "wired.transfer.data_size") ?? UInt64(0)
        let rsrcSize = message.uint64(forField: "wired.transfer.rsrc_size") ?? UInt64(0)

        if let transfer = App.transfersController.upload(path: normalizedPath,
                                                         dataSize: dataSize,
                                                         rsrcSize: rsrcSize,
                                                         executable: false,
                                                         client: client, message: message) {
            client.transfer = transfer

            self.recordEvent(.transferStartedFileUpload, client: client, parameters: [normalizedPath])

            do {
                try client.socket.set(interactive: false)
            } catch {
                App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
                client.state = .DISCONNECTED
                client.transfer = nil
                return
            }

            if !App.transfersController.run(transfer: transfer, client: client, message: message) {
                self.recordEvent(
                    .transferStoppedFileUpload,
                    client: client,
                    parameters: [normalizedPath, String(transfer.actualTransferred ?? 0)]
                )
                App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
                client.state = .DISCONNECTED
            } else {
                self.recordEvent(
                    .transferCompletedFileUpload,
                    client: client,
                    parameters: [normalizedPath, String(transfer.actualTransferred ?? 0)]
                )
            }

            client.transfer = nil
        } else {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
        }
    }

    func receiveUploadDirectory(_ client: Client, _ message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        if !user.hasPrivilege(name: "wired.account.transfer.upload_directories") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let path = message.string(forField: "wired.file.path") else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        if !File.isValid(path: path) {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }

        let normalizedPath = NSString(string: path).standardizingPath
        let realPath = App.filesController.real(path: normalizedPath)

        if let privilege = App.filesController.dropBoxPrivileges(forVirtualPath: normalizedPath) {
            if !user.hasPermission(toWrite: privilege) {
                App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                return
            }
        }

        let parentPath = realPath.stringByDeletingLastPathComponent

        guard let parentType = File.FileType.type(path: parentPath) else {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }

        if parentType == .directory && !user.hasPrivilege(name: "wired.account.transfer.upload_anywhere") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        do {
            try FileManager.default.createDirectory(atPath: realPath,
                                                    withIntermediateDirectories: true,
                                                    attributes: [FileAttributeKey.posixPermissions: 0o755])
        } catch {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }

        if parentType != .directory {
            _ = File.FileType.set(type: parentType, path: realPath)
        }

        App.indexController.addIndex(forPath: realPath)
        App.filesController.notifyDirectoryChanged(path: normalizedPath.stringByDeletingLastPathComponent)
        App.serverController.replyOK(client: client, message: message)
        self.recordEvent(.transferCompletedDirectoryUpload, client: client, parameters: [normalizedPath])
    }
}
