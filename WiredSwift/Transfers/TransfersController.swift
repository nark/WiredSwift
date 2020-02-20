//
//  TransfersController.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 20/02/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa

extension Notification.Name {
    static let didAddTransfer = Notification.Name("didAddTransfer")
}


public class TransfersController {
    public static let shared = TransfersController()
    
    var transfers:[Transfer] = []
    
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
        
        transfers.append(transfer)
        
        NotificationCenter.default.post(name: .didAddTransfer, object: transfer)
        
        return true
    }
    
    private func upload(_ path:String, toFile file:File) -> Bool {
        let transfer = UploadTransfer(file.connection)
        
        NotificationCenter.default.post(name: .didAddTransfer, object: transfer)
        
        return true
    }
    
    
    private func defaultDownloadDestination(forFile file:File) -> String? {
        if let downloadDirectory = UserDefaults.standard.string(forKey: "WSDownloadDirectory") as NSString? {
        
            return downloadDirectory.appendingPathComponent(file.name)
        }
        return nil
    }
}
