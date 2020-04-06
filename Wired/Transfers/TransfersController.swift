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






public class TransfersController {
    public static let shared = TransfersController()
    
    //var transfers:[Transfer] = []
    let semaphore = DispatchSemaphore(value: 2)
    var queue:DispatchQueue = DispatchQueue(label: "transfers-queue", qos: .utility, attributes: .concurrent)
    
    private init() {
        NotificationCenter.default.addObserver(
            self, selector:#selector(linkConnectionWillDisconnect(_:)) ,
            name: .linkConnectionWillDisconnect, object: nil)
        
        NotificationCenter.default.addObserver(
            self, selector:#selector(linkConnectionDidClose(_:)) ,
            name: .linkConnectionDidClose, object: nil)
        
        for transfer in self.transfers() {
            if transfer.state == .Disconnecting {
                transfer.state = .Disconnected
            }
        }
                
        try? AppDelegate.shared.persistentContainer.viewContext.save()
    }
    
    
    @objc func linkConnectionWillDisconnect(_ n:Notification) {
        if let connection = n.object as? Connection {
            print("linkConnectionWillDisconnect")
            for transfer in self.transfers() {
                if transfer.connection == connection && transfer.isWorking() {
                    transfer.state = .Disconnecting
                                                            
                    DispatchQueue.main.async {
                        try? AppDelegate.shared.persistentContainer.viewContext.save()
                        NotificationCenter.default.post(name: .didUpdateTransfers, object: transfer)
                    }
                }
            
            }
        }
    }
    
    
    @objc func linkConnectionDidClose(_ n:Notification) {

    }
    
    
    public func transfers() -> [Transfer] {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Transfer")
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "startDate", ascending: false)]
        
        let context = AppDelegate.shared.persistentContainer.viewContext
        
        do {
            let results = try context.fetch(fetchRequest)
            let transfers = results as! [Transfer]
            
            return transfers
            
        } catch let error as NSError {
            print("Could not fetch \(error)")
        }
        
        return []
    }
    
    
    public func remove(_ transfer:Transfer) {
        if transfer.isWorking() {
            transfer.state = .Removing
        }
        else {
            let context = AppDelegate.shared.persistentContainer.viewContext

            context.delete(transfer)
            try? context.save()
        }
        
        NotificationCenter.default.post(name: .didUpdateTransfers, object: transfer)
    }
    
    
    public func download(_ file:File) -> Bool {
        guard let downloadPath = self.temporaryDownloadDestination(forPath: file.path!) else {
            return false
        }
        
        return download(file, toPath: downloadPath)
    }
        
    
    public func download(_ file:File, toPath:String? = nil) -> Bool {
        let transfer = DownloadTransfer(context: AppDelegate.shared.persistentContainer.viewContext)
        
        transfer.name = file.name!
        transfer.connection = file.connection
        transfer.uri = file.connection.URI
        transfer.file = file
        transfer.remotePath = file.path!
        transfer.localPath = self.defaultDownloadDestination(forPath: transfer.remotePath!)
        transfer.size = Int64(file.dataSize)
        transfer.startDate = Date()
        
        try? AppDelegate.shared.persistentContainer.viewContext.save()
        
        NotificationCenter.default.post(name: .didUpdateTransfers, object: transfer)
        
        self.request(transfer)
        
        return true
    }
    
    
    public func upload(_ path:String, toDirectory destination:File) -> Bool {
        let remotePath = (destination.path as NSString).appendingPathComponent((path as NSString).lastPathComponent)
        let transfer = UploadTransfer(context: AppDelegate.shared.persistentContainer.viewContext)
        
        let file = File(remotePath, connection: destination.connection)
        file.uploadDataSize = FileManager.sizeOfFile(atPath: path)
        
        transfer.name = (path as NSString).lastPathComponent
        transfer.connection = destination.connection
        transfer.uri = file.connection.URI
        transfer.remotePath = remotePath
        transfer.localPath = path
        transfer.file = file
        transfer.size = Int64(file.uploadDataSize + file.uploadRsrcSize)
        transfer.startDate = Date()
                    
        try? AppDelegate.shared.persistentContainer.viewContext.save()
        
        NotificationCenter.default.post(name: .didUpdateTransfers, object: transfer)
        
        self.request(transfer)
        
        return true
    }
    
    
    
    public func request(_ transfer: Transfer) {
        if transfer.isFolder {
            
        } else {
            // recover connection if needed
            if transfer.connection == nil {
                if let cwc = AppDelegate.windowController(forURI: transfer.uri!) {
                    transfer.connection = cwc.connection
                    
                    // let fc = ConnectionsController.shared.filesController(forConnection: cwc.connection)
                    //transfer.file =
                }
            }
            
            self.start(transfer)
        }
    }
    
    
    public func start(_ transfer: Transfer) {
        
        if !transfer.isTerminating() {
            transfer.state = .Waiting
        }
        
        NotificationCenter.default.post(name: .didUpdateTransfers, object: transfer)
        
        self.transferThread(transfer)
    }
    
    
    private func finish(_ transfer: Transfer) {
        if transfer.state == .Pausing || transfer.state == .Paused {
            transfer.transferConnection?.disconnect()
            transfer.state = .Paused
            
        }
        else if transfer.state == .Stopping || transfer.state == .Stopped {
            transfer.transferConnection?.disconnect()
            transfer.state = .Stopped
            
        } else {
            transfer.transferConnection?.disconnect()
            transfer.state = .Finished
        }
        
        try? AppDelegate.shared.persistentContainer.viewContext.save()
        NotificationCenter.default.post(name: .didUpdateTransfers, object: transfer)
    }
    
    private func finish(_ transfer: Transfer, withError error:WiredError? = nil) {
        if let e = error {
            transfer.error = e.message
            
            AppDelegate.showWiredError(e)
            
            Logger.error(e)
        }
        
        self.finish(transfer)
    }
    
    
    private func transferThread(_ transfer: Transfer) {
        semaphore.wait()
        
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
        var error:WiredError? = nil
        var data = true
        var dataLength:UInt64? = 0
        var rsrcLength:UInt64? = 0
        let start:TimeInterval = Date.timeIntervalSinceReferenceDate
        
        if transfer.transferConnection == nil {
            transfer.transferConnection = self.transfertConnectionForTransfer(transfer)
        }
        
        let connection = transfer.transferConnection
        
        transfer.transferConnection?.interactive = false
        
        // create a secondary connection
        if (connection?.connect(withUrl: transfer.connection.url) == false) {
            transfer.state = .Stopped
            
            self.semaphore.signal()
            
            DispatchQueue.main.async {
                let downloaderror = NSLocalizedString("Download Error", comment: "")
                let transfercannotconnect = NSLocalizedString("Transfer cannot connect", comment: "")
                error = WiredError(withTitle: downloaderror, message: transfercannotconnect)
                
                Logger.error(error!)
                
                self.finish(transfer, withError: error)
            }
            
            return
        }
                
        // recover remote file on transfer connection if needed
        if transfer.file == nil {
            let message = P7Message(withName: "wired.file.get_info", spec: transfer.transferConnection!.spec)
            message.addParameter(field: "wired.file.path", value: transfer.remotePath)
            
            if transfer.transferConnection!.send(message: message) == true {
                if let response = transfer.transferConnection!.readMessage() {
                    transfer.file = File(response, connection: transfer.transferConnection!)
                }
            }
        }
            
        // request download
        if self.sendDownloadFileMessage(onConnection: connection!, forTransfer: transfer) == false {
            if (transfer.isTerminating() == false) {
                transfer.state = .Disconnecting
            }
            
            self.semaphore.signal()
            
            DispatchQueue.main.async {
                let downloaderror = NSLocalizedString("Download Error", comment: "")
                let transfercannot = NSLocalizedString("Transfer cannot download file", comment: "")
                error = WiredError(withTitle: downloaderror, message: transfercannot)
                
                Logger.error(error!)
                
                self.finish(transfer, withError: error)
            }
            
            return
        }
        
        // run download
        guard let runMessage = self.run(transfer.transferConnection!, forTransfer: transfer, untilReceivingMessageName: "wired.transfer.download") else {
            if transfer.isTerminating() == false {
                transfer.state = .Disconnecting
            }
            
            self.semaphore.signal()
                     
            DispatchQueue.main.async {
                self.finish(transfer)
            }
            
            return
        }
                        
        dataLength = runMessage.uint64(forField: "wired.transfer.data")
        rsrcLength = runMessage.uint64(forField: "wired.transfer.rsrc")
        
        let dataPath = self.temporaryDownloadDestination(forPath: transfer.remotePath!)
        let rsrcPath = FileManager.resourceForkPath(forPath: dataPath!)
        
        // check if final file alreayd exists, ask for overwrite
        if FileManager.default.fileExists(atPath: transfer.localPath!) {
            do {
                let attr = try FileManager.default.attributesOfItem(atPath: transfer.localPath!)
                let fileSize = attr[FileAttributeKey.size] as! UInt64
                
                if fileSize == dataLength! {
                    transfer.state = .Stopped
                    
                    self.semaphore.signal()
                                            
                    DispatchQueue.main.async {
                        transfer.state = .Stopped
                        
                        self.finish(transfer)
                        
                        let alert = NSAlert()
                        let filealreadyexists = NSLocalizedString("File already exists", comment: "")
                        alert.messageText = filealreadyexists
                        let doyouwanttooverwrite = NSLocalizedString("Do you want to overwrite", comment: "")
                        alert.informativeText = doyouwanttooverwrite + " '\(transfer.localPath!)'?"
                        alert.alertStyle = .warning
                        let Yes = NSLocalizedString("Yes", comment: "")
                        alert.addButton(withTitle: Yes)
                        let Cancel = NSLocalizedString("Cancel", comment: "")
                        alert.addButton(withTitle: Cancel)
                        
                        if let mainWindow = NSApp.mainWindow {
                            AppDelegate.shared.showTransfers(self)
                            alert.beginSheetModal(for: mainWindow) { (modalResponse: NSApplication.ModalResponse) -> Void in
                                if modalResponse == .alertFirstButtonReturn {
                                    // remove existing file
                                    do {
                                        try FileManager.default.removeItem(atPath: transfer.localPath!)
                                        
                                        transfer.state = .Waiting
                                        
                                        self.request(transfer)
                                        
                                    } catch let e {
                                        let downloaderror = NSLocalizedString("Download Error", comment: "")
                                        error = WiredError(withTitle: downloaderror, message: "\(e)")
                                        
                                        transfer.state = .Disconnecting
                                        
                                        self.finish(transfer, withError: error)
                                    }
                                    
                                    return
                                    
                                } else {
                                    do {
                                        try FileManager.default.removeItem(atPath: dataPath!)
                                        transfer.dataTransferred = 0
                                        transfer.rsrcTransferred = 0
                                        transfer.actualTransferred = 0
                                        transfer.speed = 0
                                        transfer.percent = 0
                                        transfer.state = .Stopped
                                        
                                        self.finish(transfer)
                                        
                                    } catch let e {
                                        let downloaderror = NSLocalizedString("Download Error", comment: "")
                                        error = WiredError(withTitle: downloaderror, message: "\(e)")
                                        
                                        transfer.state = .Disconnecting
                                        
                                        self.finish(transfer, withError: error)
                                    }

                                    
                                    return
                                }
                            }
                        }
                    }
                
                }
            } catch let e {
                self.semaphore.signal()
                
                let downloaderror = NSLocalizedString("Download Error", comment: "")
                error = WiredError(withTitle: downloaderror, message: "IO Error: \(e)")
                
                Logger.error(error!)
                
                self.finish(transfer, withError: error)
            }
        }
        
        if let finderInfo = runMessage.data(forField: "wired.transfer.finderinfo") {
            if finderInfo.count > 0 {
                // TODO: set finder info
            }
        }
        
        if transfer.isTerminating() == false {
            transfer.state = .Running
            
            // TODO: validate buttons here?
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .didUpdateTransfers, object: transfer)
            }
        }
                        
        while(transfer.isTerminating() == false) {
            if data == true && dataLength == 0 {
                data = false
            }
            
            if data == false && rsrcLength == 0 {
                break
            }
            
            guard let oobdata = transfer.transferConnection!.socket.readOOB() else {
                transfer.state = .Disconnecting
                
                break
            }
                        
            if oobdata.count <= 0 {
                transfer.state = .Disconnecting

                break
            }
            
            // actually write data
            if FileManager.default.fileExists(atPath: dataPath!) {
                if let fileHandle = FileHandle(forWritingAtPath: dataPath!) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(oobdata)
                    fileHandle.closeFile()
                } else {
                    DispatchQueue.main.async {
                        let downloaderror = NSLocalizedString("Download Error", comment: "")
                        error = WiredError(withTitle: downloaderror, message: "Transfer failed")
                        
                        Logger.error(error!)
                    }
                    break
                }
            } else {
                do {
                    try oobdata.write(to: URL(fileURLWithPath: data ? dataPath! : rsrcPath), options: .atomicWrite)
                } catch let e {
                    DispatchQueue.main.async {
                        let downloaderror = NSLocalizedString("Download Error", comment: "")
                        let transferfailed = NSLocalizedString("Transfer failed", comment: "")
                        error = WiredError(withTitle: downloaderror, message: transferfailed + " \(e)")
                        
                        Logger.error(error!)
                    }
                    
                    break
                }
            }
                        
            // update transfered data offsets
            if data {
                transfer.dataTransferred += Int64(oobdata.count)
            } else {
                transfer.rsrcTransferred += Int64(oobdata.count)
            }
            
            let totalTransferSize = transfer.file!.dataSize + transfer.file!.rsrcSize
            transfer.actualTransferred += Int64(oobdata.count)
            
            let percent         =  Double(transfer.actualTransferred) / Double(totalTransferSize) * 100.0
            transfer.percent    = percent
            
            let speed           = (Double(transfer.actualTransferred) / (Date.timeIntervalSinceReferenceDate - start)) * 8.0
            transfer.speed      = 0.5 * speed + (1 - 0.5) * transfer.speed
                        
            // update progress in view
            if let progressIndicator = transfer.progressIndicator {
                DispatchQueue.main.async {
                    progressIndicator.isIndeterminate = false
                    progressIndicator.doubleValue = percent
                    transfer.transferStatusField?.stringValue = transfer.transferStatus()
                }
            }
                        
            // transfer done
            if transfer.dataTransferred + transfer.rsrcTransferred >= transfer.file!.dataSize + transfer.file!.rsrcSize {
                transfer.state = .Disconnecting
                                
                // move to final path
                do {
                    try FileManager.default.moveItem(atPath: dataPath!, toPath: self.defaultDownloadDestination(forPath: transfer.remotePath!)!)
                } catch let e {
                    DispatchQueue.main.async {
                        let downloaderror = NSLocalizedString("Download Error", comment: "")
                        let transferrenamefailed = NSLocalizedString("Transfer rename failed", comment: "")
                        error = WiredError(withTitle: downloaderror, message: transferrenamefailed + " \(e)")
                        
                        Logger.error(error!)
                    }
                }
                

                break
            }
        }
        
        self.semaphore.signal()
        
        try? AppDelegate.shared.persistentContainer.viewContext.save()
        
        DispatchQueue.main.async {
            self.finish(transfer)
        }
    }
    
    
    private func runUpload(_ transfer: Transfer) {
        var error:WiredError? = nil
        var dataOffset:UInt64? = 0
        var dataLength:UInt64? = 0
        var sendBytes:UInt64 = 0
        var data = true
        let start:TimeInterval = Date.timeIntervalSinceReferenceDate
                
        if transfer.transferConnection == nil {
            transfer.transferConnection = self.transfertConnectionForTransfer(transfer)
        }
        
        let connection = transfer.transferConnection
        
        transfer.transferConnection?.interactive = false
        
        if connection?.connect(withUrl: transfer.connection.url) == false {
            transfer.state = .Stopped
            
            self.semaphore.signal()
            
            DispatchQueue.main.async {
                let uploaderror = NSLocalizedString("Upload Error", comment: "")
                let transfercannotconnect = NSLocalizedString("Transfer cannot connect", comment: "")
                error = WiredError(withTitle: uploaderror, message: transfercannotconnect)
                
                Logger.error(error!)

                self.finish(transfer, withError: error)
            }

            return
        }
        
        if self.sendUploadFileMessage(onConnection: connection!, forTransfer: transfer) == false {
            if transfer.isTerminating() == false {
                transfer.state = .Disconnecting
            }
            
            self.semaphore.signal()
            
            DispatchQueue.main.async {
                let uploaderror = NSLocalizedString("Upload Error", comment: "")
                let transfercannotuploadfile = NSLocalizedString("Transfer cannot upload file", comment: "")
                error = WiredError(withTitle: uploaderror, message: transfercannotuploadfile)
                
                Logger.error(error!)
                
                self.finish(transfer, withError: error)
            }
            
            return
        }
        
        guard let message = self.run(transfer.transferConnection!, forTransfer: transfer, untilReceivingMessageName: "wired.transfer.upload_ready") else {
            if transfer.isTerminating() == false {
                transfer.state = .Disconnecting
            }
            
            self.semaphore.signal()
                     
            DispatchQueue.main.async {
                self.finish(transfer)
            }
            
            return
        }
        
        dataOffset = message.uint64(forField: "wired.transfer.data_offset")
        dataLength = transfer.file!.uploadDataSize - dataOffset!
        
        if transfer.file!.dataTransferred == 0 {
            transfer.file!.dataTransferred = dataOffset!
            transfer.dataTransferred = transfer.dataTransferred + Int64(dataOffset!)
        } else {
            transfer.file!.dataTransferred = dataOffset!
            transfer.dataTransferred = Int64(dataOffset!)
        }
        
        if self.sendUploadMessage(onConnection: connection!, forTransfer: transfer, dataLength: dataLength!, rsrcLength: 0) == false {
            if transfer.isTerminating() == false {
                transfer.state = .Disconnecting
            }
            
            self.semaphore.signal()
            
            DispatchQueue.main.async {
                let uploaderror = NSLocalizedString("Upload Error", comment: "")
                let transfercannotupload = NSLocalizedString("Transfer cannot upload", comment: "")
                error = WiredError(withTitle: uploaderror, message: transfercannotupload)
                
                Logger.error(error!)
                
                self.finish(transfer, withError: error)
            }
            
            return
        }
        
        
        if transfer.isTerminating() == false {
            transfer.state = .Running
            
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .didUpdateTransfers, object: transfer)
            }
        }
                
        if let fileHandle = FileHandle(forReadingAtPath: transfer.localPath!) {
            while transfer.isTerminating() == false {
                if data && dataLength == 0 {
                    data = false
                }
                
                if data == false {
                    break
                }
                                
                fileHandle.seek(toFileOffset: dataOffset!)
                let readData = fileHandle.readData(ofLength: 8192)
                let readBytes = readData.count
                                
                if readBytes <= 0 {
                    if transfer.isTerminating() == false {
                        transfer.state = .Disconnecting
                    }
                    
                    DispatchQueue.main.async {
                        let uploaderror = NSLocalizedString("Upload Error", comment: "")
                        let cannotreadlocaldata = NSLocalizedString("Cannot read local data", comment: "")
                        error = WiredError(withTitle: uploaderror, message: cannotreadlocaldata)

                        Logger.error(error!)
                        
                        self.finish(transfer, withError: error)
                    }
                    
                    break
                }
                
                sendBytes = (dataLength! < UInt64(readBytes)) ? dataLength! : UInt64(readBytes)
                dataOffset! += sendBytes
                
                if transfer.transferConnection!.socket.writeOOB(data: readData, timeout: 30.0) == false {
                    if transfer.isTerminating() == false {
                        transfer.state = .Disconnecting
                    }
                    
                    break
                }
                
                dataLength!                 -= sendBytes
                transfer.dataTransferred    += Int64(sendBytes)
                transfer.actualTransferred  += Int64(readBytes)
                transfer.percent            = Double(transfer.dataTransferred) / Double(transfer.size) * 100
                
                let speed                   = (Double(transfer.dataTransferred) / (Date.timeIntervalSinceReferenceDate - start)) * 8.0
                transfer.speed              = 0.5 * speed + (1 - 0.5) * transfer.speed
                
                // update progress in view
                if let progressIndicator = transfer.progressIndicator {
                    DispatchQueue.main.async {
                        progressIndicator.isIndeterminate = false
                        progressIndicator.doubleValue = transfer.percent
                        transfer.transferStatusField?.stringValue = transfer.transferStatus()
                    }
                }
            }
        
            fileHandle.closeFile()
        }
        
        self.semaphore.signal()
        
        try? AppDelegate.shared.persistentContainer.viewContext.save()
        
        DispatchQueue.main.async {
            self.finish(transfer)
        }
    }
    
    
    private func sendDownloadFileMessage(onConnection connection:TransferConnection, forTransfer transfer:Transfer) -> Bool {
        let message = P7Message(withName: "wired.transfer.download_file", spec: transfer.connection.spec)
        message.addParameter(field: "wired.file.path", value: transfer.remotePath)
        message.addParameter(field: "wired.transfer.data_offset", value: UInt64(transfer.dataTransferred))
        message.addParameter(field: "wired.transfer.rsrc_offset", value: UInt64(transfer.rsrcTransferred))
        
        if transfer.transferConnection?.send(message: message) == false {
            return false
        }
        
        return true
    }
    
    
    private func sendUploadFileMessage(onConnection connection:TransferConnection, forTransfer transfer:Transfer) -> Bool {
        let message = P7Message(withName: "wired.transfer.upload_file", spec: transfer.connection.spec)
        message.addParameter(field: "wired.file.path", value: transfer.file?.path)
        message.addParameter(field: "wired.transfer.data_size", value: UInt64(transfer.size))
        message.addParameter(field: "wired.transfer.rsrc_size", value: UInt64(0))

        if transfer.transferConnection?.send(message: message) == false {
            return false
        }
        
        return true
    }
    
    
    private func sendUploadMessage(onConnection connection:TransferConnection, forTransfer transfer:Transfer, dataLength:UInt64, rsrcLength:UInt64) -> Bool {
        let message = P7Message(withName: "wired.transfer.upload", spec: transfer.connection.spec)
        message.addParameter(field: "wired.file.path", value: transfer.file?.path)
        
        print("dataLength : \(dataLength)")
        
        var data = Data()
        data.append(uint64: dataLength.bigEndian)
        message.addParameter(field: "wired.transfer.data", value: data)
        
        data = Data()
        data.append(uint64: rsrcLength.bigEndian)
        message.addParameter(field: "wired.transfer.rsrc", value: data)
        
        data = FileManager.default.finderInfo(atPath: transfer.file!.path)!
        message.addParameter(field: "wired.transfer.finderinfo", value: data)
        
        print("message : \(message.xml())")

        if transfer.transferConnection?.send(message: message) == false {
            return false
        }
        
        return true
    }
    
    
    private func run(_ connection: TransferConnection, forTransfer transfer:Transfer, untilReceivingMessageName messageName:String) -> P7Message? {
        while transfer.isWorking() {
            guard let message = transfer.transferConnection?.readMessage() else {
                let localstring = NSLocalizedString("Transfer cannot read message, probably timed out", comment: "")
                print(localstring)
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
                    let localstring = NSLocalizedString("Transfer cannot reply ping", comment: "")
                    print(localstring)
                    return nil
                }
                
            } else if message.name == "wired.error" {
                let localstring = NSLocalizedString("Transfer error", comment: "")
                print(localstring)
                if let error = transfer.connection.spec.error(forMessage: message) {
                    let localstring = NSLocalizedString("Transfer error", comment: "")
                    print(localstring + ": \(error.name!)")
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
    
    
    private func temporaryDownloadDestination(forPath path:String) -> String? {
        if let downloadDirectory = UserDefaults.standard.string(forKey: "WSDownloadDirectory") as NSString? {
            let fileName = (path as NSString).lastPathComponent
            return (downloadDirectory.expandingTildeInPath as NSString).appendingPathComponent(fileName).appendingFormat(".%@", Wired.transfersFileExtension)
        }
        return nil
    }
    
    
    private func defaultDownloadDestination(forPath path:String) -> String? {
        if let downloadDirectory = UserDefaults.standard.string(forKey: "WSDownloadDirectory") as NSString? {
            let fileName = (path as NSString).lastPathComponent
            return (downloadDirectory.expandingTildeInPath as NSString).appendingPathComponent(fileName)
        }
        return nil
    }
}
