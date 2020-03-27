//
//  ConsoleViewController.swift
//  Wired
//
//  Created by Rafael Warnault on 26/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa

class ConsoleViewController: NSViewController, LoggerDelegate {
    @IBOutlet weak var logsTextView: NSTextView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
        Logger.delegate = self
    }
    
    
    // MARK: -
    
    func loggerDidOutput(logger: Logger, output: String) {
        let font = NSFont(name: "Courier", size: 12.0) as Any
        let attributes: [NSAttributedString.Key : Any] = [.font : font, .foregroundColor: NSColor.textColor]
        let attrString = NSAttributedString(string: output + "\n", attributes: attributes)
        
        DispatchQueue.main.async {
            let smartScroll = self.logsTextView.visibleRect.maxY == self.logsTextView.bounds.maxY

            self.logsTextView.textStorage?.append(attrString)

            if smartScroll {
                self.logsTextView.scrollToEndOfDocument(self)
            }
        }
    }
}
