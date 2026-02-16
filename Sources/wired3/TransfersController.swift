//
//  TransfersController.swift
//  wired3
//
//  Created by Rafael Warnault on 26/03/2021.
//

import Foundation
import WiredSwift
import Queuer
#if os(Linux)
import Glibc
#else
import Darwin
#endif


let WiredTransferBufferSize = 16384
let WiredTransferTimeout = 30.0
let WiredTransferPartialExtension = "WiredTransfer"



public class TransfersController {
    let filesController:FilesController
    
    var transfers:[Transfer] = []
    var usersDownloadTransfers:[String:[Transfer]] = [:]
    var usersUploadTransfers:[String:[Transfer]] = [:]
    
    let transfersLock = Lock()
    let queue = Queuer(name: "WiredTransfersQueue", maxConcurrentOperationCount: 10, qualityOfService: .default)

    // MARK: - Queueing (Wired 2/3 style)
    //
    // The original Wired transfers queue is not a simple FIFO: it recomputes queue positions
    // with fairness between users (round-robin) while respecting global and per-user
    // concurrency limits separately for downloads and uploads.
    //
    // We keep the existing `Queuer` usage (so we don't break scheduling semantics), but add
    // a lightweight queue-position layer on top. By default, limits are *disabled*, meaning
    // behaviour is identical to the previous implementation (no queue messages, immediate start).
    // Configure limits externally if/when needed.
    public var totalDownloadLimit: Int? = nil
    public var totalUploadLimit: Int? = nil
    public var perUserDownloadLimit: Int? = nil
    public var perUserUploadLimit: Int? = nil

    private struct QueueEntry {
        let queuedAt: Date
        let userKey: String
        let isDownload: Bool
        let condition: NSCondition
        var position: Int            // 0 = ready, >0 = queued position
        var reserved: Bool           // counted as active (slot reserved)
    }

    private let queueStateLock = NSLock()
    private var queueEntries: [ObjectIdentifier: QueueEntry] = [:]

    private let queueRecalcLock = NSCondition()
    private var queueNeedsRecalc: Bool = false

    private var activeDownloads: Int = 0
    private var activeUploads: Int = 0
    private var userActiveDownloads: [String: Int] = [:]
    private var userActiveUploads: [String: Int] = [:]
    
    
    
    public init(filesController: FilesController) {
        self.filesController = filesController

        // Start the queue recomputation loop.
        DispatchQueue.global(qos: .default).async { [weak self] in
            self?.queueRecomputeLoop()
        }
    }
    
    
    
    // MARK: -
    private func add(transfer:Transfer, user: User) {
        self.transfersLock.exclusivelyWrite {
            var dictionary = transfer.type == .download ? self.usersDownloadTransfers : self.usersUploadTransfers
            
            if dictionary[user.username!] == nil {
                dictionary[user.username!] = []
            }
            
            self.transfers.append(transfer)
            dictionary[user.username!]?.append(transfer)
            
            if transfer.type == .download {
                self.usersDownloadTransfers = dictionary
            } else {
                self.usersUploadTransfers   = dictionary
            }

            // Register queue entry (independent of Queuer scheduling).
            self.registerQueueEntry(for: transfer, user: user)
        }

        self.signalQueueRecalc()
    }
    
    private func remove(transfer:Transfer, user: User) {
        self.transfersLock.exclusivelyWrite {
            if let index = self.transfers.firstIndex(of: transfer) {
                self.transfers.remove(at: index)
                
                if transfer.type == .download {
                    self.usersDownloadTransfers[user.username!] = nil
                } else {
                    self.usersUploadTransfers[user.username!] = nil
                }
            }

            self.unregisterQueueEntry(for: transfer)
        }

        self.signalQueueRecalc()
    }



    // MARK: - Internal queue helpers
    private func userKey(for user: User) -> String {
        // Wired 2 uses login + ip. Here, we keep the existing mapping based on username
        // (this controller already keys dictionaries by username) to avoid breaking behaviour.
        return user.username ?? "unknown"
    }

    private func registerQueueEntry(for transfer: Transfer, user: User) {
        let id = ObjectIdentifier(transfer)
        queueStateLock.lock()
        defer { queueStateLock.unlock() }

        if queueEntries[id] != nil { return }

        let entry = QueueEntry(
            queuedAt: Date(),
            userKey: userKey(for: user),
            isDownload: (transfer.type == .download),
            condition: NSCondition(),
            position: 1,
            reserved: false
        )

        queueEntries[id] = entry
    }

    private func unregisterQueueEntry(for transfer: Transfer) {
        let id = ObjectIdentifier(transfer)
        queueStateLock.lock()
        defer { queueStateLock.unlock() }

        guard var entry = queueEntries[id] else { return }

        // If this transfer had reserved a slot, release it.
        if entry.reserved {
            if entry.isDownload {
                activeDownloads = max(0, activeDownloads - 1)
                let cur = userActiveDownloads[entry.userKey] ?? 0
                userActiveDownloads[entry.userKey] = max(0, cur - 1)
            } else {
                activeUploads = max(0, activeUploads - 1)
                let cur = userActiveUploads[entry.userKey] ?? 0
                userActiveUploads[entry.userKey] = max(0, cur - 1)
            }
            entry.reserved = false
        }

        // Wake any waiter.
        entry.condition.lock()
        entry.condition.broadcast()
        entry.condition.unlock()

        queueEntries.removeValue(forKey: id)
    }

    private func signalQueueRecalc() {
        queueRecalcLock.lock()
        queueNeedsRecalc = true
        queueRecalcLock.signal()
        queueRecalcLock.unlock()
    }

    private func queueRecomputeLoop() {
        while true {
            queueRecalcLock.lock()
            while !queueNeedsRecalc {
                queueRecalcLock.wait()
            }
            queueNeedsRecalc = false
            queueRecalcLock.unlock()

            recomputeQueuePositions()
        }
    }

    private func recomputeQueuePositions() {
        // Snapshot queued entries.
        queueStateLock.lock()
        var entries = queueEntries
        // We will mutate back under the same lock.

        // Build per-user queues (only entries that are not already ready).
        var perUser: [String: [(ObjectIdentifier, QueueEntry)]] = [:]
        for (id, entry) in entries {
            if entry.position == 0 { continue }
            perUser[entry.userKey, default: []].append((id, entry))
        }

        // Sort each user's queue by queuedAt.
        for key in perUser.keys {
            perUser[key]?.sort { $0.1.queuedAt < $1.1.queuedAt }
        }

        // Sort user keys by the oldest queued transfer in their queue.
        let sortedUserKeys = perUser.keys.sorted { a, b in
            let da = perUser[a]!.first!.1.queuedAt
            let db = perUser[b]!.first!.1.queuedAt
            return da < db
        }

        // Compute the maximum queue length.
        let longest = perUser.values.map { $0.count }.max() ?? 0
        var positionCounter = 1

        // Local counters start from current reserved slots.
        var newActiveDownloads = activeDownloads
        var newActiveUploads = activeUploads
        var newUserDownloads = userActiveDownloads
        var newUserUploads = userActiveUploads

        func canReserve(_ e: QueueEntry) -> Bool {
            if e.isDownload {
                if let lim = totalDownloadLimit, newActiveDownloads >= lim { return false }
                if let lim = perUserDownloadLimit, (newUserDownloads[e.userKey] ?? 0) >= lim { return false }
            } else {
                if let lim = totalUploadLimit, newActiveUploads >= lim { return false }
                if let lim = perUserUploadLimit, (newUserUploads[e.userKey] ?? 0) >= lim { return false }
            }
            return true
        }

        // Round-robin across users.
        for i in 0..<longest {
            for userKey in sortedUserKeys {
                guard let queue = perUser[userKey], i < queue.count else { continue }
                let (id, oldEntry) = queue[i]

                var updated = oldEntry
                let shouldBeReady = canReserve(oldEntry)

                if shouldBeReady {
                    updated.position = 0

                    if !updated.reserved {
                        updated.reserved = true
                        if updated.isDownload {
                            newActiveDownloads += 1
                            newUserDownloads[updated.userKey] = (newUserDownloads[updated.userKey] ?? 0) + 1
                        } else {
                            newActiveUploads += 1
                            newUserUploads[updated.userKey] = (newUserUploads[updated.userKey] ?? 0) + 1
                        }
                    }
                } else {
                    updated.position = positionCounter
                    positionCounter += 1
                }

                // Store updated entry.
                entries[id] = updated

                // Notify waiters if position changed.
                if updated.position != oldEntry.position {
                    updated.condition.lock()
                    updated.condition.broadcast()
                    updated.condition.unlock()
                }
            }
        }

        // Commit updated entries and counters.
        queueEntries = entries
        activeDownloads = newActiveDownloads
        activeUploads = newActiveUploads
        userActiveDownloads = newUserDownloads
        userActiveUploads = newUserUploads

        queueStateLock.unlock()
    }
    
    
    
    // MARK: -
    public func run(transfer: Transfer, client:Client, message:P7Message) -> Bool {
        var result = false
        
        self.add(transfer: transfer, user: client.user!)
        
        let runLock = Semaphore()
        let synchronousOperation = ConcurrentOperation { _ in
            if self.wait(untilReady: transfer, client: client, message: message) {
                transfer.state = .running

                if transfer.type == .download {
                    result = self.runDownload(transfer: transfer, client: client, message: message)
                } else {
                    result = self.runUpload(transfer: transfer, client: client, message: message)
                }
            }
            
            runLock.continue()
        }
        
        self.queue.addOperation(synchronousOperation)
        runLock.wait()
                
        self.remove(transfer: transfer, user: client.user!)
        
        return result
    }
    
    public func download(path:String, dataOffset:UInt64, rsrcOffset:UInt64, client:Client, message:P7Message) -> Transfer? {
        let transfer = Transfer(path: path, client: client, message: message, type: .download)
                
        transfer.dataOffset = dataOffset
        transfer.rsrcOffset = rsrcOffset
        transfer.realDataPath = filesController.real(path: path)
        
        do {
            transfer.dataFd = try FileHandle(forReadingFrom: URL(fileURLWithPath: transfer.realDataPath))
        } catch let error {
            Logger.error("Error while reading file \(error)")
            return nil
        }

        transfer.rsrcFd = nil // not implemented
        transfer.dataSize = File.size(path: transfer.realDataPath)
        transfer.rsrcSize = UInt64(0)
        transfer.transferred = dataOffset + rsrcOffset
        transfer.remainingDataSize = transfer.dataSize - dataOffset
        transfer.remainingRsrcSize = transfer.rsrcSize - rsrcOffset
        transfer.actualTransferred = UInt64(0)
        
        do {
            try transfer.dataFd.seek(toOffset: dataOffset)
        } catch let error {
            try? transfer.dataFd.close()
            Logger.error("Error \(error) seeking file \(transfer.realDataPath ?? "")")
            return nil
        }
        
        return transfer
    }
    
    public func upload(path:String, dataSize:UInt64, rsrcSize:UInt64, executable: Bool, client:Client, message:P7Message) -> Transfer? {
        let transfer = Transfer(path: path, client: client, message: message, type: .upload)
        var realPath = filesController.real(path: path)
        
        if FileManager.default.fileExists(atPath: realPath) {
            App.serverController.replyError(client: client, error: "wired.error.file_exists", message: message)
            
            return nil
        }
        
        if !realPath.hasSuffix(WiredTransferPartialExtension) {
            if let p = realPath.stringByAppendingPathExtension(ext: WiredTransferPartialExtension) {
                realPath = p
            }
        }
        
        let dataOffset = FileManager.sizeOfFile(atPath: realPath) ?? UInt64(0)
        
        let fd = open(realPath, O_WRONLY | O_APPEND | O_CREAT, S_IWUSR | S_IRUSR);
        
        if(fd < 0) {
            Logger.error("Could not open upload \(realPath)")
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return nil
        }
        
        if lseek(fd, off_t(dataOffset), SEEK_SET) < 0 {
            Logger.error("Could not seek to \(dataOffset) in upload \(realPath)")
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return nil
        }
        
        let rsrcOffset = UInt64(0)
        
        if rsrcSize > 0 {
            // TODO: implement RSRC here
        }
        else {
            //realrsrcpath    = NULL;
            // rsrcOffset = 0
            //rsrcfd          = -1;
        }
        
        transfer.dataFd = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        transfer.dataOffset = dataOffset
        transfer.realDataPath = realPath
        transfer.dataSize = dataSize
        transfer.rsrcSize = rsrcSize
        transfer.dataOffset = dataOffset
        transfer.rsrcOffset = UInt64(0)
        transfer.transferred = dataOffset + rsrcOffset
        transfer.executable = false
        transfer.remainingDataSize = dataSize - dataOffset
        transfer.remainingRsrcSize = rsrcSize - rsrcOffset
        transfer.actualTransferred = UInt64(0)
        
        return transfer
    }
    
    
    // MARK: -
    private func wait(untilReady transfer:Transfer, client:Client, message:P7Message) -> Bool {
        // Make sure we have at least one recompute pass.
        self.signalQueueRecalc()

        let id = ObjectIdentifier(transfer)

        while client.state == .LOGGED_IN {
            // Snapshot current queue position.
            queueStateLock.lock()
            guard let entry = queueEntries[id] else {
                queueStateLock.unlock()
                return false
            }
            let position = entry.position
            let cond = entry.condition
            queueStateLock.unlock()

            if position == 0 {
                return true
            }

            // Only send queue messages when we are actually queued.
            let reply = P7Message(withName: "wired.transfer.queue", spec: message.spec)
            reply.addParameter(field: "wired.file.path", value: transfer.path)
            reply.addParameter(field: "wired.transfer.queue_position", value: UInt32(position))
            if let t = message.uint32(forField: "wired.transaction") {
                reply.addParameter(field: "wired.transaction", value: t)
            }
            if !client.socket.write(reply) {
                return false
            }

            // Wait until the queue thread recomputes (or timeout to re-send position).
            cond.lock()
            _ = cond.wait(until: Date().addingTimeInterval(1.0))
            cond.unlock()
        }

        return false
        
    }
    
    private func runDownload(transfer: Transfer, client:Client, message:P7Message) -> Bool {
//        var remainingDataSize = Data()
//        remainingDataSize.append(uint64: transfer.remainingDataSize.bigEndian)
//
//        var remainingRsrcSize = Data()
//        remainingRsrcSize.append(uint64: transfer.remainingRsrcSize.bigEndian)
        
        let reply = P7Message(withName: "wired.transfer.download", spec: message.spec)
        reply.addParameter(field: "wired.file.path", value: transfer.path)
        reply.addParameter(field: "wired.transfer.data", value: transfer.remainingDataSize)
        reply.addParameter(field: "wired.transfer.rsrc", value: transfer.remainingRsrcSize)
        reply.addParameter(field: "wired.transfer.finderinfo", value: FileManager.default.finderInfo(atPath: transfer.realDataPath))
        
        if let t = message.uint32(forField: "wired.transaction") {
            reply.addParameter(field: "wired.transaction", value: t)
        }
                
        if !transfer.client.socket.write(reply) {
            Logger.error("Could not write message \(reply.name!) to \(client.user!.username!)")
            return false
        }
        
        do {
            try client.socket.set(interactive: false)
        } catch let error {
            return false
        }
        
        let result = self.download(transfer: transfer)
        
        do {
            try client.socket.set(interactive: true)
        } catch let error {
            return false
        }

        return result
    }
    
    
    private func runUpload(transfer: Transfer, client:Client, message:P7Message) -> Bool {
        let reply = P7Message(withName: "wired.transfer.upload_ready", spec: message.spec)
        reply.addParameter(field: "wired.file.path", value: transfer.path)
        reply.addParameter(field: "wired.transfer.data_offset", value: transfer.dataOffset)
        reply.addParameter(field: "wired.transfer.rsrc_offset", value: transfer.rsrcOffset)
        
        if let t = message.uint32(forField: "wired.transaction") {
            reply.addParameter(field: "wired.transaction", value: t)
        }
                        
        if !transfer.client.socket.write(reply) {
            Logger.error("Could not write message \(reply.name!) to \(client.user!.username!)")
            return false
        }
        
        guard let reply2 = try? transfer.client.socket.readMessage() else {
            Logger.error("Could not read message from \(client.user!.username!) while waiting for upload \(transfer.path)")
            return false
        }
        
        if reply2.name != "wired.transfer.upload" {
            Logger.error("Could not accept message \(reply2.name!) from \(client.user!.username!): Expected 'wired.transfer.upload'")
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: reply2)
        }

        transfer.remainingDataSize = reply2.uint64(forField: "wired.transfer.data")
        transfer.remainingRsrcSize = reply2.uint64(forField: "wired.transfer.rsrc")

        do {
            try client.socket.set(interactive: false)
        } catch {
            return false
        }

        let result = self.upload(transfer: transfer)

        do {
            try client.socket.set(interactive: true)
        } catch {
            return false
        }
        
        if transfer.transferred == (transfer.dataSize + transfer.rsrcSize) {
            let url = URL(fileURLWithPath: transfer.realDataPath.stringByDeletingPathExtension)

            do {
                try FileManager.default.moveItem(at: URL(fileURLWithPath: transfer.realDataPath), to: url)

                if transfer.executable {
                    if !FileManager.set(mode: 0o777, toPath: url.path) {
                        Logger.error("Could not set mode for executable \(url.path)")
                    }

//                    wd_files_move_comment(transfer->realdatapath, path, NULL, NULL);
//                    wd_files_move_label(transfer->realdatapath, path, NULL, NULL);
//
//                    if(wi_data_length(transfer->finderinfo) > 0)
//                        wi_fs_set_finder_info_for_path(transfer->finderinfo, path);

                    App.indexController.addIndex(forPath: url.path)
                }
            } catch let error {
                Logger.error("Could not move \(transfer.realDataPath!) to \(url.path): \(error)")
            }
        }

        return result
        return true
    }
    
    
    private func download(transfer: Transfer) -> Bool {
        var data = true
        var result = true
        var sendbytes:UInt64 = 0
        //let transfers = self.transfers[transfer.user.username!]
        
        while transfer.client.state == .LOGGED_IN {
            if data && transfer.remainingDataSize == 0 {
                data = false
            }
            
            if !data && transfer.remainingRsrcSize == 0 {
                break
            }
            
            let buffer = transfer.dataFd.readData(ofLength: WiredTransferBufferSize)
            let readbytes = UInt64(buffer.count)
            
            if readbytes <= 0 {
                Logger.error("Could not read download from \(transfer.realDataPath!)")
                
                result = false
                break
            }
            
            // TODO: wait timeout ?
            
            if(transfer.client.state != .LOGGED_IN) {
                result = false
                break
            }
            
            if data {
                sendbytes = (transfer.remainingDataSize < readbytes) ? transfer.remainingDataSize : readbytes
            } else {
                sendbytes = (transfer.remainingRsrcSize < readbytes) ? transfer.remainingRsrcSize : readbytes
            }
            
            do {
                let write = try transfer.client.socket.writeOOB(data: buffer, timeout: WiredTransferTimeout)
            } catch {
                Logger.error("Could not write download to \(transfer.client.user!.username!)")
                
                result = false
                break
            }
            
            if(data) {
                transfer.remainingDataSize -= sendbytes
            } else {
                transfer.remainingRsrcSize -= sendbytes
            }
            
            transfer.transferred        += sendbytes
            transfer.actualTransferred  += sendbytes
        }
        
        return result
    }
    
    
    private func upload(transfer: Transfer) -> Bool {
        var data = true
        var result = true
                
        while transfer.client.state == .LOGGED_IN {
            if transfer.remainingDataSize == 0 {
                data = false
            }
            
            if !data && transfer.remainingRsrcSize == 0 {
                break
            }
            
            // TODO: wait timeout ?
            
            if(transfer.client.state != .LOGGED_IN) {
                result = false
                break
            }
            
            guard let inData = try? transfer.client.socket.readOOB(timeout: WiredTransferTimeout) else {
                Logger.error("Could not read upload from \(transfer.realDataPath!)")

                result = false
                break
            }
            
            var readBytes:UInt64 = 0
            
            let writtenBytes: Int = inData.withUnsafeBytes { rawBuffer in
                readBytes = UInt64(rawBuffer.count)
                
                guard let baseAddress = rawBuffer.baseAddress else {
                    return -1
                }

                return write(
                    transfer.dataFd.fileDescriptor,
                    baseAddress,
                    rawBuffer.count
                )
            }

            if writtenBytes <= 0 {
                if writtenBytes < 0 {
                    Logger.error("Could not write upload \(transfer.realDataPath!) to \(transfer.client.user!.username!)")
                }
                
                result = false
                break
            }
            
            if(data) {
                transfer.remainingDataSize -= readBytes
            } else {
                transfer.remainingRsrcSize -= readBytes
            }
            
            transfer.transferred        += readBytes
            transfer.actualTransferred  += readBytes
        }
        
        return result
    }
}
