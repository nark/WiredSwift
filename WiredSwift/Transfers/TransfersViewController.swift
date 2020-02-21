//
//  TransfersViewController.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 20/02/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa

class TransfersViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    @IBOutlet weak var transfersTableView: NSTableView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
        
        NotificationCenter.default.addObserver(self, selector:  #selector(didUpdateTransfers), name: .didUpdateTransfers, object: nil)
    }
    
    
    @objc func didUpdateTransfers(_ notification: Notification) {
        if let transfer = notification.object as? Transfer {
            print("didUpdateTransfers: \(transfer)")
            transfersTableView.reloadData()
        }
    }
    
    
    
    // MARK: -
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return TransfersController.shared.transfers.count
    }


    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        var view: TransferCell?
        
        view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "TransferCell"), owner: self) as? TransferCell
        
        let transfer = TransfersController.shared.transfers[row]
        
        if let file = transfer.file {
            view?.fileName.stringValue = file.name
        }
        
        view?.transferInfo.stringValue = "\(transfer.state)"

        return view
    }
    
}

