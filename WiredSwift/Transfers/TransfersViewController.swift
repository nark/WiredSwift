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
        
        NotificationCenter.default.addObserver(self, selector:  #selector(didAddTransfer(_:)), name: .didAddTransfer, object: nil)
    }
    
    
    @objc func didAddTransfer(_ notification: Notification) {
        if let transfer = notification.object as? Transfer {
            print("didAddTransfer: \(transfer)")
            transfersTableView.reloadData()
        }
    }
    
    
    
    // MARK: -
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return TransfersController.shared.transfers.count
    }


    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        var view: NSTableCellView?
        
        view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "TransferCell"), owner: self) as? UserCellView
        
//        view?.userNick?.stringValue = self.users[row].nick
//        view?.userStatus?.stringValue = self.users[row].status
//
//        if self.users[row].idle == true {
//            view?.alphaValue = 0.5
//        } else {
//            view?.alphaValue = 1.0
//        }

        return view
    }
    
}

