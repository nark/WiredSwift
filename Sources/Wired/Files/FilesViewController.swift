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


class FilesViewController: ConnectionViewController, ConnectionDelegate, NSBrowserDelegate, NSOutlineViewDelegate, NSOutlineViewDataSource {
    @IBOutlet weak var browser: NSBrowser!
    @IBOutlet weak var outlineView: NSOutlineView!
    @IBOutlet weak var progressIndicator: NSProgressIndicator!

    @IBOutlet weak var historySegmentedControl: NSSegmentedControl!
    @IBOutlet weak var downloadButton: NSButton!
    @IBOutlet weak var uploadButton: NSButton!
    
    var filesController:FilesController!
    var filePreviewController:FilePreviewController!
    
    var currentRoot:File!
    
    var backHistory:[File] = []
    var forwardHistory:[File] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        browser.setCellClass(FileCell.self)
        browser.target = self
        browser.doubleAction = #selector(doubleClickFile)
        
        outlineView.target = self
        outlineView.doubleAction = #selector(doubleClickFile)
        
        NotificationCenter.default.addObserver(self, selector:  #selector(didLoadDirectory(_:)), name: .didLoadDirectory, object: nil)
        UserDefaults.standard.addObserver(self, forKeyPath: "WSSelectedFilesViewType", options: NSKeyValueObservingOptions.new, context: nil)
    }
    
    
    override func viewDidAppear() {
        super.viewDidAppear()
    }
    
    override var representedObject: Any? {
        didSet {
            if let conn = self.representedObject as? ServerConnection {
                self.connection = conn
                self.filesController = ConnectionsController.shared.filesController(forConnection: self.connection)
                
                self.connection.delegates.append(self)
                
                self.filesController.load(ofFile: nil)
                self.currentRoot = self.filesController.rootFile
                
                self.progressIndicator.startAnimation(self)
                
            }
        }
    }
    

    
    
    // MARK: -
    @IBAction func reload(_ sender: Any) {
        self.filesController.load(ofFile: self.currentRoot, reload: true)
        self.progressIndicator.startAnimation(self)
    }
    
    @IBAction func download(_ sender: Any) {
        if let file = selectedFile() {
            self.downloadFile(file)
        }
    }
    
    @IBAction func upload(_ sender: Any) {
        var file = selectedFile()
        
        if file == nil {
            if UserDefaults.standard.integer(forKey: "WSSelectedFilesViewType") == 0 {
                file = self.currentRoot
            }
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
    
    @IBAction func historyAction(_ sender: Any) {
        if let sc = sender as? NSSegmentedControl {
            if sc.selectedSegment == 0 {
                // go back
                self.forwardHistory.append(self.currentRoot)
                
                if let f = self.backHistory.popLast() {
                     self.changeRoot(withFile: f)
                }
                
            } else if sc.selectedSegment == 1 {
                // go forward
                self.backHistory.append(self.currentRoot)
                
                if let f = self.forwardHistory.popLast() {
                     self.changeRoot(withFile: f)
                }
            }
        }
    }
    
    
    // MARK: -
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "WSSelectedFilesViewType" {
            self.browser.reloadColumn(self.browser.lastColumn)
            self.validate()
        }
    }
    
    @objc func didLoadDirectory(_ notification: Notification) {
        if let file = notification.object as? File {
            //let columnIndex = file.path.split(separator: "/").count
            
            if self.filesController == nil {
                return
            }
                        
            // reload outline
            if file == self.currentRoot {
                self.outlineView.reloadData()
            } else {
                self.outlineView.reloadItem(file, reloadChildren: true)
            }
            
            // reload browser
//            if self.browser.lastColumn != -1 {
//                self.browser.reloadColumn(self.browser.lastColumn)
//            }
            
            self.progressIndicator.stopAnimation(self)
            
            self.validate()
        }
    }
    
    
    @objc private func doubleClickFile() {
        if let file = selectedFile() {
            if file.isFolder() {
                if UserDefaults.standard.integer(forKey: "WSSelectedFilesViewType") == 0 {
                    self.backHistory.append(self.currentRoot)
                    self.forwardHistory.removeAll()
                    
                    self.changeRoot(withFile: file)
                    
                    self.progressIndicator.startAnimation(self)
                }
                
            } else {
                self.downloadFile(file)
            }
        }
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
    
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if self.filesController == nil {
            return 0
        }
        
        if let file = item as? File {
            return file.children.count
        }
        return self.currentRoot.children.count
    }
    
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let file = item as? File {
            return file.children[index]
        }
        return self.currentRoot.children[index]
    }
    
    
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if let f = item as? File {
            return f.type != .file
        }
        
        return true
    }
    
    
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        var view: NSTableCellView?
        
        view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "FileCell"), owner: self) as? NSTableCellView
        
        if let f = item as? File {
            if tableColumn?.identifier.rawValue == "Name" {
                view?.textField?.stringValue = f.name
                
                if let icon = f.icon() {
                    icon.size = NSMakeSize(16.0, 16.0)
                    view?.imageView?.image = icon
                }
            }
            else if tableColumn?.identifier.rawValue == "Size" {
                view?.textField?.stringValue = f.isFolder() ? "\(f.directoryCount) items" : AppDelegate.byteCountFormatter.string(fromByteCount: Int64(f.dataSize))
            }
            else if tableColumn?.identifier.rawValue == "Modified" {
                view?.textField?.stringValue = ""
            }
            else if tableColumn?.identifier.rawValue == "Created" {
                view?.textField?.stringValue = ""
            }
            else if tableColumn?.identifier.rawValue == "Type" {
                view?.imageView?.image = nil
                view?.textField?.stringValue = f.fileType()
            }
        }
        
        return view
    }
    
    
    func outlineViewItemDidExpand(_ notification: Notification) {
        if (notification.object as? NSOutlineView) == outlineView {
            if let file = notification.userInfo?["NSObject"] as? File {
                self.filesController.load(ofFile: file)
                self.progressIndicator.startAnimation(self)
            }
        }
        
        self.validate()
    }
    
    
    func outlineViewSelectionDidChange(_ notification: Notification) {
        self.validate()
        
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
        
        self.validate()
        
        return proposedSelectionIndexes;
    }
    
    func browser(_ browser: NSBrowser, numberOfChildrenOfItem item: Any?) -> Int {
        if let file = item as? File {
            return file.children.count
        }
        return self.currentRoot.children.count
    }
    
    func browser(_ browser: NSBrowser, child index: Int, ofItem item: Any?) -> Any {
        if let file = item as? File {
            return file.children[index]
        }
        return self.currentRoot.children[index]
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
    
    
    
    // MARK: - Private
    
    
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
    
    
    private func downloadFile(_ file:File) {
        if !file.isFolder() { // for now
            if TransfersController.shared.download(file) {
                AppDelegate.shared.showTransfers(self)
            }
        }
    }
    
    
    private func selectedFile() -> File? {
        var column  = browser.selectedColumn
        var row     = browser.clickedRow
        
        if UserDefaults.standard.integer(forKey: "WSSelectedFilesViewType") == 0 {
            if outlineView.clickedRow != -1 {
                row = outlineView.clickedRow
            }
            
            if outlineView.selectedRow != -1 {
                row = outlineView.selectedRow
            }
            
            if row != -1 {
                return outlineView.item(atRow: row) as? File
            }
            
        } else if UserDefaults.standard.integer(forKey: "WSSelectedFilesViewType") == 1 {
            if browser.clickedColumn == -1 {
                column = browser.selectedColumn
            }
            
            if browser.clickedRow == -1 {
                row = browser.selectedRow(inColumn: column)
            }
            
            if row != -1 && column != -1 {
                if let clickedItem = browser.item(atRow: row, inColumn: column) {
                    if let file = clickedItem as? File {
                        return file
                    }
                }
            }
        }
        return nil
    }
    
    
    private func changeRoot(withFile file: File) {
        if file.isFolder() {
            self.currentRoot = file
            
            self.outlineView.reloadData()
            self.browser.reloadColumn(0)
            
            self.filesController.load(ofFile: file)
            self.progressIndicator.startAnimation(self)
        }

        self.validate()
    }
    
    
    
    private func validate() {
        if self.connection != nil && self.connection.isConnected() {
            if UserDefaults.standard.integer(forKey: "WSSelectedFilesViewType") == 1 {
                historySegmentedControl.setEnabled(!self.backHistory.isEmpty, forSegment: 0)
                historySegmentedControl.setEnabled(!self.forwardHistory.isEmpty, forSegment: 1)
            }
        } else {
            historySegmentedControl.setEnabled(false, forSegment: 0)
            historySegmentedControl.setEnabled(false, forSegment: 1)
        }
        
        downloadButton.isEnabled = self.selectedFile() != nil && !self.selectedFile()!.isFolder()
        uploadButton.isEnabled = self.selectedFile() != nil && self.selectedFile()!.isFolder() // is upload folder
    }
}
