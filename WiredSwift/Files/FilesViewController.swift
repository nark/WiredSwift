//
//  FilesViewController.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 19/02/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa


class FileCell: NSBrowserCell {
    override init(imageCell i: NSImage?) {
        super.init(imageCell: i)
        isLeaf = true
    }
    
    override init(textCell s: String) {
        super.init(textCell: s)
        isLeaf = true
    }
    
    required init(coder c: NSCoder) {
        super.init(coder: c)
        isLeaf = true
    }
}


class FilesViewController: ConnectionController, ConnectionDelegate, NSBrowserDelegate {
    @IBOutlet weak var browser: NSBrowser!
    @IBOutlet weak var progressIndicator: NSProgressIndicator!
    
    var filesController:FilesController!
    var filePreviewController:FilePreviewController!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        browser.setCellClass(FileCell.self)
        browser.target = self
        browser.doubleAction = #selector(doubleClickFile)
        
        NotificationCenter.default.addObserver(self, selector:  #selector(didLoadDirectory(_:)), name: .didLoadDirectory, object: nil)
    }
    
    
    override func viewDidAppear() {
        super.viewDidAppear()
    }
    
    override var representedObject: Any? {
        didSet {
            if let conn = self.representedObject as? Connection {
                self.connection = conn
                self.filesController = ConnectionsController.shared.filesController(forConnection: self.connection)
                
                self.connection.delegates.append(self)
                
                self.filesController.load(ofFile: nil)
                self.progressIndicator.startAnimation(self)
                self.updateView()
            }
        }
    }
    
    
    private func updateView() {        
        if self.connection != nil {
            //self.filesController.load(ofFile: nil)
        }
    }
    
    
    
    // MARK: -
    
    @IBAction func download(_ sender: Any) {
        if let file = selectedFile() {
            self.downloadFile(file)
        }
    }
    
    @IBAction func upload(_ sender: Any) {
        var file = selectedFile()
        
        if file == nil {
            file = self.filesController.rootFile
        }
        
        if file!.isFolder() {
            let openPanel = NSOpenPanel()
            openPanel.canChooseFiles = true
            openPanel.allowsMultipleSelection = false
            openPanel.canChooseDirectories = false
            openPanel.canCreateDirectories = false
            openPanel.title = title
        
            openPanel.beginSheetModal(for:self.view.window!) { (response) in
                if response == .OK {
                    let selectedPath = openPanel.url!.path

                    if TransfersController.shared.upload(selectedPath, toDirectory:file!) {
                        AppDelegate.shared.showTransfers(self)
                    }
                }
                openPanel.close()
            }
        }
    }
    
    
    
    // MARK: -
    
    @objc func didLoadDirectory(_ notification: Notification) {
        if let file = notification.object as? File {
            let columnIndex = file.path.split(separator: "/").count
            
            //print("columnIndex : \(columnIndex)")
            
            browser.reloadColumn(columnIndex)
            self.progressIndicator.stopAnimation(self)
        }
    }
    
    
    @objc private func doubleClickFile() {
        if let file = selectedFile() {
            self.downloadFile(file)
        }
    }
    
    
    private func downloadFile(_ file:File) {
        if !file.isFolder() { // for now
            if TransfersController.shared.download(file) {
                AppDelegate.shared.showTransfers(self)
            }
        }
    }
    
    
    private func selectedFile() -> File? {
        var column  = browser.clickedColumn
        var row     = browser.clickedRow
        
        if browser.clickedColumn == -1 {
            column = browser.selectedColumn
        }
        
        if browser.clickedRow == -1 {
            row = browser.selectedRow(inColumn: column)
        }

        print("row : \(row)")
        print("column : \(column)")
        
        if row != -1 && column != -1 {
            if let clickedItem = browser.item(atRow: row, inColumn: column) {
                if let file = clickedItem as? File {
                    return file
                }
            }
        }
        return nil
    }
    
    
    
    // MARK: -
    
    func connectionDidConnect(connection: Connection) {
        
    }
    
    func connectionDidFailToConnect(connection: Connection, error: Error) {
        
    }
    
    func connectionDisconnected(connection: Connection, error: Error?) {
    
    }
    
    func connectionDidReceiveMessage(connection: Connection, message: P7Message) {

    }
    
    func connectionDidReceiveError(connection: Connection, message: P7Message) {
        
    }
    
    // MARK: -

    func browser(_ browser: NSBrowser, selectionIndexesForProposedSelection proposedSelectionIndexes: IndexSet, inColumn column: Int) -> IndexSet {
        if let index = proposedSelectionIndexes.first {
            if let file = browser.item(atRow: index, inColumn: column) as? File {
                if file.isFolder() && file.children.count == 0 {
                    self.filesController.load(ofFile: file)
                    self.progressIndicator.startAnimation(self)
                }
            }
        }
        
        return proposedSelectionIndexes;
    }
    
    func browser(_ browser: NSBrowser, numberOfChildrenOfItem item: Any?) -> Int {
        if let file = item as? File {
            return file.children.count
        }
        return self.filesController.rootFile.children.count
    }
    
    func browser(_ browser: NSBrowser, child index: Int, ofItem item: Any?) -> Any {
        if let file = item as? File {
            return file.children[index]
        }
        return self.filesController.rootFile.children[index]
    }
    
    
    func browser(_ browser: NSBrowser, isLeafItem item: Any?) -> Bool {
        if let f = item as? File {
            return f.type == .file
        }
        return true
    }
    
    
    func browser(_ browser: NSBrowser, objectValueForItem item: Any?) -> Any? {
        if let f = item as? File {
            return f.name
        }
        return "nil"
    }
    
    func browser(_ sender: NSBrowser, willDisplayCell cell: Any, atRow row: Int, column: Int) {
        if let f = sender.item(atRow: row, inColumn: column) as? File {
            if let theCell = cell as? FileCell {
                //theCell.isLeaf = f.type == .file
                if let icon = f.icon() {
                    icon.size = NSMakeSize(16.0, 16.0)
                    theCell.image = icon
                }
            }
        }
    }
    
    func browser(_ browser: NSBrowser, previewViewControllerForLeafItem item: Any) -> NSViewController? {
        filePreviewController = FilePreviewController(nibName: "FilePreviewController", bundle: Bundle.main)
        filePreviewController.loadView()
                
        if let file = item as? File {
            self.updatePreview(forFile: file)
        } else {
            self.updatePreview(forFile: nil)
        }
        return filePreviewController
    }
    
    
    private func updatePreview(forFile file:File?) {
        if let f = file {
            if let icon = f.icon() {
                icon.size = NSMakeSize(128.0, 128.0)
                filePreviewController.iconView.image = icon
            }
            filePreviewController.filenameLabel.stringValue = f.name
            filePreviewController.typeLabel.stringValue = f.fileType()
            filePreviewController.sizeLabel.stringValue = self.format(bytes: Double(f.dataSize))
        } else {
            filePreviewController.iconView.image = nil
            filePreviewController.filenameLabel.stringValue = ""
            filePreviewController.typeLabel.stringValue = ""
            filePreviewController.sizeLabel.stringValue = ""
        }
    }
    
    
    // TODO: move to extensions/framework
    private func format(bytes: Double) -> String {
        guard bytes > 0 else {
            return "0 bytes"
        }

        // Adapted from http://stackoverflow.com/a/18650828
        let suffixes = ["bytes", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"]
        let k: Double = 1000
        let i = floor(log(bytes) / log(k))

        // Format number with thousands separator and everything below 1 GB with no decimal places.
        let numberFormatter = NumberFormatter()
        numberFormatter.maximumFractionDigits = i < 3 ? 0 : 1
        numberFormatter.numberStyle = .decimal

        let numberString = numberFormatter.string(from: NSNumber(value: bytes / pow(k, i))) ?? "Unknown"
        let suffix = suffixes[Int(i)]
        return "\(numberString) \(suffix)"
    }
}
