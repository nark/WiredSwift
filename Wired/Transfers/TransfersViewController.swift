//
//  TransfersViewController.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 20/02/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa

class TransfersViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSUserInterfaceValidations
{
    
    @IBOutlet weak var transfersTableView: NSTableView!
    
    @IBOutlet weak var startButton: NSButton!
    @IBOutlet weak var stopButton: NSButton!
    @IBOutlet weak var pauseButton: NSButton!
    @IBOutlet weak var removeButton: NSButton!
    @IBOutlet weak var clearButton: NSButton!
    @IBOutlet weak var revealButton: NSButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
        
        NotificationCenter.default.addObserver(self, selector:  #selector(didUpdateTransfers), name: .didUpdateTransfers, object: nil)
            
        self.validate()
    }
    
    
    @objc func didUpdateTransfers(_ notification: Notification) {
        if let transfer = notification.object as? Transfer {
            transfersTableView.reloadData()
            // maybe better to reload at index only
        }
        
        transfersTableView.reloadData()
        self.validate()
    }
    
    
    
    // MARK: -
    
    @IBAction func startTransfer(_ sender: Any) {
        if let selectedTransfer = self.selectedTransfer() {
            selectedTransfer.state = .Waiting
            
            TransfersController.shared.request(selectedTransfer)
        }
        
        transfersTableView.setNeedsDisplay(transfersTableView.frame)
        self.validate()
    }
    
    @IBAction func stopTransfer(_ sender: Any) {
        if let selectedTransfer = self.selectedTransfer() {
            selectedTransfer.state = .Stopping
            
           // TransfersController.shared.stop(selectedTransfer)
        }
        
        transfersTableView.setNeedsDisplay(transfersTableView.frame)
        self.validate()
    }
    
    @IBAction func pauseTransfer(_ sender: Any) {
        let selectecRow = transfersTableView.selectedRow
        
        if let selectedTransfer = self.selectedTransfer() {
            
            selectedTransfer.state = .Pausing
        }
        
        //transfersTableView.setNeedsDisplay(transfersTableView.frame)
        //transfersTableView.selectRowIndexes([selectecRow], byExtendingSelection: false)
        transfersTableView.reloadData(forRowIndexes: [selectecRow], columnIndexes: [0])
        self.validate()
    }
    
    @IBAction func removeTransfer(_ sender: Any) {
        if let selectedTransfer = self.selectedTransfer() {
            TransfersController.shared.remove(selectedTransfer)
            self.transfersTableView.deselectAll(sender)
            self.validate()
        }
    }
    
    @IBAction func clearTransfers(_ sender: Any) {
        for t in TransfersController.shared.transfers() {
            if t.state == .Finished {
                TransfersController.shared.remove(t)
                self.validate()
            }
        }
    }
    
    @IBAction func revealInFinder(_ sender: Any) {
        let selectecRow = transfersTableView.selectedRow
        
        if selectecRow != -1 {
            let selectedTransfer = TransfersController.shared.transfers()[selectecRow]
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: selectedTransfer.localPath!)])
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
    
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        self.validate()
    }
    
    
    // MARK: -
    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(startTransfer(_:)) {
            if let transfer = self.selectedTransfer() {
                return !transfer.isWorking() && !transfer.isTerminating() && transfer.state != .Finished
            }
        }
        else if item.action == #selector(stopTransfer(_:)) {
            if let transfer = self.selectedTransfer() {
                return transfer.isWorking()
            }
        }
        else if item.action == #selector(pauseTransfer(_:)) {
            if let transfer = self.selectedTransfer() {
                return transfer.isWorking()
            }
        }
        else if item.action == #selector(removeTransfer(_:)) {
            if let transfer = self.selectedTransfer() {
                return !transfer.isWorking()
            }
        }
        else if item.action == #selector(clearTransfers(_:)) {
            return true
        }
        else if item.action == #selector(revealInFinder(_:)) {
            if nil != self.selectedTransfer() {
                return true
            }
        }

        return false
    }

    
    
    // MARK: -
    
    private func selectedTransfer() -> Transfer? {
        if transfersTableView.clickedRow != -1 {
            return TransfersController.shared.transfers()[transfersTableView.clickedRow]
        }
        
        if transfersTableView.selectedRow != -1 {
            return TransfersController.shared.transfers()[transfersTableView.selectedRow]
        }
        return nil
    }
    
    
    private func validate() {
        if transfersTableView.selectedRow != -1 {
            let transfer = TransfersController.shared.transfers()[transfersTableView.selectedRow]
            
            self.startButton.isEnabled  = !transfer.isWorking() && !transfer.isTerminating() && transfer.state != .Finished
            self.stopButton.isEnabled   = transfer.isWorking()
            self.pauseButton.isEnabled  = transfer.isWorking()
            self.removeButton.isEnabled = !transfer.isWorking()
            self.clearButton.isEnabled  = true
            self.revealButton.isEnabled = true
        } else {
            self.startButton.isEnabled  = false
            self.stopButton.isEnabled   = false
            self.pauseButton.isEnabled  = false
            self.removeButton.isEnabled = false
            self.clearButton.isEnabled  = true
            self.revealButton.isEnabled = false
        }
    }
}

