/*
 MIT License
 
 Copyright (c) 2017-2018 MessageKit
 
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in all
 copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 SOFTWARE.
 */

import AppKit
import MessageKit_macOS

class ViewController: NSViewController {
  
  @IBOutlet weak var messageBox: GrowingTextField!
  
  @IBOutlet weak var sendButton: NSButton!
  
  weak var conversationViewController: ConversationViewController!
  
  override func viewDidLoad() {
    
  }
  
  override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
    
    if let conversationViewController = segue.destinationController as? ConversationViewController {
      self.conversationViewController = conversationViewController
    }
    
  }
  
  @IBAction func doSend(_ sender: NSButton) {
    
    let message = messageBox.stringValue
    
    if message.isEmpty {
      return
    }
    
    conversationViewController.addMessage(message: message)
    
    messageBox.stringValue = ""
    
  }
  
  //  override func viewDidLoad() {
  //    super.viewDidLoad()
  //
  //
  //    let conversationViewController = ConversationViewController()
  //    addChild(conversationViewController)
  //
  //
  //    let conversationView = conversationViewController.view
  //
  //    conversationView.translatesAutoresizingMaskIntoConstraints = false
  //    view.addSubview(conversationView)
  //
  //    let messageInputBar = GrowingTextView()
  //    messageInputBar.textContainerInset = NSSize(width: 4, height: 4)
  //    messageInputBar.isRichText = false
  //    messageInputBar.translatesAutoresizingMaskIntoConstraints = false
  //    messageInputBar.wantsLayer = true
  //    messageInputBar.allowsImageEditing = true
  //    messageInputBar.importsGraphics = true
  //    messageInputBar.layer?.borderWidth = 1
  //    messageInputBar.layer?.borderColor = NSColor.black.cgColor
  //    messageInputBar.layer?.cornerRadius = 8
  //
  //    view.addSubview(messageInputBar)
  //
  //    let sendButton = NSButton()
  //    sendButton.title = "Send"
  //    sendButton.translatesAutoresizingMaskIntoConstraints = false
  //
  //    view.addSubview(sendButton)
  //
  //    view.bottomAnchor.constraint(equalTo: sendButton.bottomAnchor).isActive = true
  //    view.trailingAnchor.constraint(equalTo: sendButton.trailingAnchor).isActive = true
  //    messageInputBar.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor).isActive = true
  //
  //    //messageInputBar.heightAnchor.constraint(lessThanOrEqualToConstant: 200).isActive = true
  //
  //    view.topAnchor.constraint(equalTo: conversationView.topAnchor).isActive = true
  //    view.leadingAnchor.constraint(equalTo: conversationView.leadingAnchor).isActive = true
  //    view.trailingAnchor.constraint(equalTo: conversationView.trailingAnchor).isActive = true
  //
  //    conversationView.bottomAnchor.constraint(equalTo: messageInputBar.topAnchor, constant: -8).isActive = true
  //
  //    view.leadingAnchor.constraint(equalTo: messageInputBar.leadingAnchor, constant: -8).isActive = true
  ////    view.trailingAnchor.constraint(equalTo: messageInputBar.trailingAnchor, constant: 8).isActive = true
  //    view.bottomAnchor.constraint(equalTo: messageInputBar.bottomAnchor, constant: 8).isActive = true
  //
  //    //messageInputBar.delegate = conversationViewController
  //
  //  }
  
}

