//
//  TransfersController.swift
//  wired3
//
//  Created by Rafael Warnault on 26/03/2021.
//

import Foundation
import WiredSwift
import Queuer


let WiredTransferBufferSize = 16384
let WiredTransferTimeout = 30.0
let WiredTransferPartialExtension = "WiredTransfer"



public class TransfersController {
    let filesController:FilesController
    
    var transfers:[Transfer] = []
    var usersDownloadTransfers:[String:[Transfer]] = [:]
    var usersUploadTransfers:[String:[Transfer]] = [:]
    
    let transfersLock = DispatchSemaphore(value: 1)
    let queue = Queuer(name: "WiredTransfersQueue", maxConcurrentOperationCount: 10, qualityOfService: .default)
    
    
    
    public init(filesController: FilesController) {
        self.filesController = filesController
    }
    
    
    
    // MARK: -
    private func add(transfer:Transfer, user: User) {
        self.transfersLock.wait()
        
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
        
        self.transfersLock.signal()
    }
    
    private func remove(transfer:Transfer, user: User) {
        self.transfersLock.wait()
        
        if let index = self.transfers.firstIndex(of: transfer) {
            self.transfers.remove(at: index)
            
            if transfer.type == .download {
                self.usersDownloadTransfers[user.username!] = nil
            } else {
                self.usersUploadTransfers[user.username!] = nil
            }
        }
        
        self.transfersLock.signal()
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
//        while true {
//            let reply = P7Message(withName: "wired.transfer.queue", spec: message.spec)
//            reply.addParameter(field: "wired.file.path", value: transfer.path)
//            reply.addParameter(field: "wired.transfer.queue_position", value: UInt32(0))
//
//            if let t = message.uint32(forField: "wired.transaction") {
//                reply.addParameter(field: "wired.transaction", value: t)
//            }
//
//            if !user.socket!.write(reply) {
//                return false
//            }
//        }
        return true
        
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
        
        client.socket.set(interactive: false)
        
        let result = self.download(transfer: transfer)
        
        client.socket.set(interactive: true)

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
        
        print("before write ready")
                
        if !transfer.client.socket.write(reply) {
            Logger.error("Could not write message \(reply.name!) to \(client.user!.username!)")
            return false
        }
        
        
                        
        print("before read \(client.state)")

        guard let reply2 = transfer.client.socket.readMessage() else {
            Logger.error("Could not read message from \(client.user!.username!) while waiting for upload \(transfer.path)")
            return false
        }
        print("after read \(reply2)")

        if reply2.name != "wired.transfer.upload" {
            Logger.error("Could not accept message \(reply2.name!) from \(client.user!.username!): Expected 'wired.transfer.upload'")
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: reply2)
        }

        transfer.remainingDataSize = reply2.uint64(forField: "wired.transfer.data")
        transfer.remainingRsrcSize = reply2.uint64(forField: "wired.transfer.rsrc")

        client.socket.set(interactive: false)

        let result = self.upload(transfer: transfer)

        client.socket.set(interactive: true)
        
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

                    App.indexController.add(path: url.path)
                }
            } catch let error {
                Logger.error("Could not move \(transfer.realDataPath!) to \(url.path): \(error)")
            }
        }

        return result
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
            
            if let  write = transfer.client.socket?.writeOOB(data: buffer, timeout: WiredTransferTimeout),
                    write == false {
                Logger.error("Could not write download to \(transfer.client.user!.username!)")
                
                result = false
                break
            } else {
                //Logger.debug("Wrote \(sendbytes) to \(transfer.user.username!)")
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
        
        print("upload : \(transfer.client.state)")
        
        while transfer.client.state == .LOGGED_IN {
            
            print("while loop ok")
            
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
            
            guard let buffer = transfer.client.socket.readOOB(timeout: WiredTransferTimeout) else {
                Logger.error("Could not read upload from \(transfer.realDataPath!)")

                result = false
                break
            }
            
            let readBytes = UInt64(buffer.count)
            let writtenBytes = write(transfer.dataFd.fileDescriptor, buffer.bytes, Int(readBytes))

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
