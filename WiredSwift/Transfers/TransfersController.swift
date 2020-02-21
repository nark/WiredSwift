//
//  TransfersController.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 20/02/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//





import Cocoa



extension Notification.Name {
    static let didUpdateTransfers = Notification.Name("didAddTransfer")
}



extension FileManager {
    public static func resourceForkPath(forPath path:String) -> String {
        var nspath = path as NSString
        
        nspath = nspath.appendingPathComponent("..namedfork") as NSString
        nspath = nspath.appendingPathComponent("rsrc") as NSString
        
        return nspath as String
    }
    
    
    public func setFinderInfo(_ finderInfo: Data, atPath path:String) -> Bool {
        return true
    }
}



public class TransfersController {
    public static let shared = TransfersController()
    
    var transfers:[Transfer] = []
    var queue:DispatchQueue = DispatchQueue(label: "transfers-queue", qos: .utility)
    
    private init() {

    }
    
    
    public func download(_ file:File) -> Bool {
        guard let downloadPath = self.defaultDownloadDestination(forFile: file) else {
            return false
        }
        
        return download(file, toPath: downloadPath)
    }
        
    
    private func download(_ file:File, toPath:String? = nil) -> Bool {
        let transfer = DownloadTransfer(file.connection)
        
        transfer.file = file
        
        transfers.append(transfer)
                
        NotificationCenter.default.post(name: .didUpdateTransfers, object: transfer)
        
        self.request(transfer)
        
        return true
    }
    
    
    private func upload(_ path:String, toFile file:File) -> Bool {
        let transfer = UploadTransfer(file.connection)
            
        NotificationCenter.default.post(name: .didUpdateTransfers, object: transfer)
        
        self.request(transfer)
        
        return true
    }
    
    
    
    private func request(_ transfer: Transfer) {
        if transfer.file?.isFolder() == true {
            
        } else {
            self.start(transfer)
        }
    }
    
    
    private func start(_ transfer: Transfer) {
        NotificationCenter.default.post(name: .didUpdateTransfers, object: transfer)

        if !transfer.isTerminating() {
            transfer.state = .Waiting
        }
        
        self.transferThread(transfer)
    }
    
    
    private func finish(_ transfer: Transfer) {
        transfer.transferConnection?.disconnect()
        transfer.state = .Finished
        
        NotificationCenter.default.post(name: .didUpdateTransfers, object: transfer)
    }
    
    private func finish(_ transfer: Transfer, withError error:String? = nil) {
        if error != nil {
            print("Transfer error: \(error)")
        }
        
        NotificationCenter.default.post(name: .didUpdateTransfers, object: transfer)
    }
    
    
    private func transferThread(_ transfer: Transfer) {
        queue.async {
            if transfer is DownloadTransfer {
                self.runDownload(transfer)
            }
            else if transfer is UploadTransfer {
                self.runUpload(transfer)
            }
        }
    }
    
    
    private func runDownload(_ transfer: Transfer) {
        var buffer:Data = Data()
        var error:String? = nil
        var data = true
        var dataLength:UInt64? = 0
        var rsrcLength:UInt64? = 0
        var readBytes = 0
        var writtenBytes = 0
        
        print("runDownload")
        
        if transfer.transferConnection == nil {
            transfer.transferConnection = self.transfertConnectionForTransfer(transfer)
        }
        
        let connection = transfer.transferConnection
        
        transfer.transferConnection?.interactive = false
        
        if (connection?.connect(withUrl: transfer.connection.url) == false) {
            transfer.state = .Stopped
            
            DispatchQueue.main.async {
                error = "Transfer cannot connect"
                
                Logger.error(error!)
                
                self.finish(transfer, withError: error)
            }
            
            return
        }
        
        
        
        let message = P7Message(withName: "wired.transfer.download_file", spec: transfer.connection.spec)
        message.addParameter(field: "wired.file.path", value: transfer.file?.path)
        message.addParameter(field: "wired.transfer.data_offset", value: UInt64(0))
        message.addParameter(field: "wired.transfer.rsrc_offset", value: UInt64(0))

        if transfer.transferConnection?.send(message: message) == false {
            if (transfer.isTerminating() == false) {
                transfer.state = .Disconnecting
            }
            
            DispatchQueue.main.async {
                error = "Transfer cannot download_file"
                
                Logger.error(error!)
                
                self.finish(transfer, withError: error)
            }
            
            return
        }
        
        guard let runMessage = self.run(transfer.transferConnection!, forTransfer: transfer, untilReceivingMessageName: "wired.transfer.download") else {
            return
        }
        
        print("run : \(runMessage.xml(pretty: true))")
        
        dataLength = runMessage.uint64(forField: "wired.transfer.data")
        rsrcLength = runMessage.uint64(forField: "wired.transfer.rsrc")

        print("dataLength: \(dataLength!)")
        
        let dataPath = self.defaultDownloadDestination(forFile: transfer.file!)
        let rsrcPath = FileManager.resourceForkPath(forPath: dataPath!)
        
        print("dataPath : \(dataPath!)")
        print("rsrcPath : \(rsrcPath)")
        
        let dataFD = open(dataPath!, O_WRONLY | O_APPEND | O_CREAT, 0666 as mode_t)
        let rsrcFD = open(rsrcPath, O_WRONLY | O_APPEND | O_CREAT, 0666 as mode_t)
        
        print("dataFD : \(dataFD)")
        print("rsrcFD : \(rsrcFD)")
                
//        if( (dataFD < 0 || lseek(dataFD, off_t(transfer.file!.dataTransferred), SEEK_SET) < 0) ||
//            (rsrcFD < 0 || lseek(rsrcFD, off_t(transfer.file!.rsrcTransferred), SEEK_SET) < 0)) {
//            error = "Transfer POSIX error"
//
//            if transfer.isTerminating() == false {
//                transfer.state = .Disconnecting
//            }
//
//            if dataFD >= 0 {
//                close(dataFD)
//            }
//            if rsrcFD >= 0 {
//                close(rsrcFD)
//            }
//
//            self.finish(transfer, withError: error)
//
//            return
//        }
        
        print("lseek")
        
        if let finderInfo = message.data(forField: "wired.transfer.finderinfo") {
            if finderInfo.count > 0 {
                // set finder info
            }
        }
        
        if transfer.isTerminating() == false {
            transfer.state = .Running
            
            // validate buttons here
        }
        
        print("before while")
        
        while(transfer.isTerminating() == false) {
            if data == true && dataLength == 0 {
                data = false
            }
            
            if data == false && rsrcLength == 0 {
                break
            }
            
            
            readBytes = transfer.transferConnection!.socket.readOOB(buffer)
            
            print(readBytes)
            
            if readBytes <= 0 {
                transfer.state = .Disconnecting

                break
            }
            
//            if((data && dataLength != nil && dataLength! < UInt32(readBytes)) || (data == false && rsrcLength != nil && rsrcLength! < UInt32(readBytes))) {
//                DispatchQueue.main.async {
//                    error = "Transfer failed"
//
//                    Logger.error(error!)
//                }
//                break
//            }
            
            buffer.withUnsafeBytes { rawBufferPointer in
                let rawPtr = rawBufferPointer.baseAddress!
                print("write")
                writtenBytes = write(data ? dataFD : rsrcFD, rawPtr, readBytes)
            }
            
            if writtenBytes <= 0 {
                if writtenBytes < 0 {
                    DispatchQueue.main.async {
                        error = "Transfer failed"
                        
                        Logger.error(error!)
                    }
                }
                break
            }
            
            
        }
        
        close(dataFD)
        close(rsrcFD)
        
        DispatchQueue.main.async {
            self.finish(transfer)
        }
    }
    
    
    private func runUpload(_ transfert: Transfer) {
        print("runUpload")
    }
    
    
    private func run(_ connection: TransferConnection, forTransfer transfer:Transfer, untilReceivingMessageName messageName:String) -> P7Message? {
        while transfer.isWorking() {
            guard let message = transfer.transferConnection?.readMessage() else {
                print("Transfer cannot read message, probably timed out")
                return nil
            }
            
            if message.name == messageName {
                return message
            }
            
            if message.name == "wired.transfer.queue" {
                
            } else if message.name == "wired.transfer.send_ping" {
                let reply = P7Message(withName: "wired.ping", spec: transfer.connection.spec)
                
                if let t = message.uint32(forField: "wired.transaction") {
                    reply.addParameter(field: "wired.transaction", value: t)
                }
                
                if transfer.transferConnection?.send(message: message) == false {
                    print("Transfer cannot reply ping")
                    return nil
                }
                
            } else if message.name == "wired.error" {
                if let error = transfer.connection.spec.error(forMessage: message) {
                    print("Transfer error: \(error.name!)")
                }
                return nil
            }
        }
        return nil
    }
    
    
    private func transfertConnectionForTransfer(_ transfer: Transfer) -> TransferConnection {
        let connection = TransferConnection(withSpec: transfer.connection.spec, transfer: transfer)
        
        connection.nick   = transfer.connection.nick
        connection.status = transfer.connection.status
        connection.icon   = transfer.connection.icon
        
        return connection
    }
    
    private func defaultDownloadDestination(forFile file:File) -> String? {
        if let downloadDirectory = UserDefaults.standard.string(forKey: "WSDownloadDirectory") as NSString? {
        
            return (downloadDirectory.expandingTildeInPath as NSString).appendingPathComponent(file.name)
        }
        return nil
    }
}
