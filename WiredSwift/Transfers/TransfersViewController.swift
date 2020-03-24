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
            transfersTableView.reloadData()
            // maybe better to reload at index only
        } else {
            transfersTableView.reloadData()
        }
    }
    
    
    
    // MARK: -
    
    @IBAction func startTransfer(_ sender: Any) {
        if transfersTableView.selectedRow != -1 {
            let selectedTransfer = TransfersController.shared.transfers()[transfersTableView.selectedRow]
        
            selectedTransfer.state = .Waiting
            
            TransfersController.shared.request(selectedTransfer)
        }
        
        transfersTableView.setNeedsDisplay(transfersTableView.frame)
    }
    
    @IBAction func stopTransfer(_ sender: Any) {
        if transfersTableView.selectedRow != -1 {
            let selectedTransfer = TransfersController.shared.transfers()[transfersTableView.selectedRow]
            
            selectedTransfer.state = .Pausing
            
           // TransfersController.shared.stop(selectedTransfer)
        }
        
        transfersTableView.setNeedsDisplay(transfersTableView.frame)
    }
    
    @IBAction func pauseTransfer(_ sender: Any) {
        let selectecRow = transfersTableView.selectedRow
        
        if selectecRow != -1 {
            let selectedTransfer = TransfersController.shared.transfers()[selectecRow]
            
            selectedTransfer.state = .Pausing
        }
        
        //transfersTableView.setNeedsDisplay(transfersTableView.frame)
        //transfersTableView.selectRowIndexes([selectecRow], byExtendingSelection: false)
        transfersTableView.reloadData(forRowIndexes: [selectecRow], columnIndexes: [0])
    }
    
    @IBAction func removeTransfer(_ sender: Any) {
        if transfersTableView.selectedRow != -1 {
            let selectedTransfer = TransfersController.shared.transfers()[transfersTableView.selectedRow]
            
            TransfersController.shared.remove(selectedTransfer)
        }
    }
    
    @IBAction func clearTransfers(_ sender: Any) {
        for t in TransfersController.shared.transfers() {
            if t.state == .Finished {
                TransfersController.shared.remove(t)
            }
        }
    }
    
    
    
    // MARK: -
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return TransfersController.shared.transfers().count
    }


    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        var view: TransferCell?
        
        view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "TransferCell"), owner: self) as? TransferCell
        
        let transfer = TransfersController.shared.transfers()[row]
        
        if let name = transfer.name {
            view?.fileName.stringValue = name
        }
        
        view?.progressIndicator.isIndeterminate = false
        view?.progressIndicator.doubleValue = transfer.percent
        
        transfer.progressIndicator?.usesThreadedAnimation = true
        transfer.progressIndicator?.startAnimation(self)
        transfer.progressIndicator = view?.progressIndicator
        transfer.transferStatusField = view?.transferInfo
        
        view?.transferInfo.stringValue = transfer.transferStatus()

        return view
    }
    
}

