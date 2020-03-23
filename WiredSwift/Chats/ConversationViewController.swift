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
import MapKit

class ConversationViewController: MessagesViewController {
    public var connection: Connection!
    
    var messageList: [Any] = []
    var isTyping = false
    let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        messagesCollectionView.messagesDataSource = self
        messagesCollectionView.messagesLayoutDelegate = self
        messagesCollectionView.messagesDisplayDelegate = self
        messagesCollectionView.messageCellDelegate = self
        //        messageInputBar.delegate = self

        //messageInputBar.sendButton.tintColor = UIColor(red: 69/255, green: 193/255, blue: 89/255, alpha: 1)
        scrollsToBottomOnKeybordBeginsEditing = true // default false
        maintainPositionOnKeyboardFrameChanged = true // default false

    }
    
    
    func addChatMessage(message: String, fromUser user: UserInfo, me:Bool = true) {
        var senderID = "\(user.userID!)"
        
        if me { senderID = "111111" }
        
        let sender = Sender(id: senderID, displayName: user.nick)
        let msg = ChatMessage(text: message, sender: sender, messageId: UUID().uuidString, date: Date())
        
        self.messageList.append(msg)
        self.messagesCollectionView.insertItemAfterLast()
        self.messagesCollectionView.scrollToBottom(animated: false)
    }
    
    func addPrivateMessage(message: String, cdMessage:Message, me:Bool = true) {
        var senderID = "\(cdMessage.userID)"
        
        if me { senderID = "111111" }
        
        let sender = Sender(id: senderID, displayName: cdMessage.nick!)
        let msg = PrivateMessage(text: message, sender: sender, messageId: cdMessage.objectID.uriRepresentation().absoluteString, date: Date())
        
        self.messageList.append(msg)
        self.messagesCollectionView.insertItemAfterLast()
        self.messagesCollectionView.scrollToBottom(animated: false)
    }
  
    func addEventMessage(message: String) {
        let msg = EventMessage(text: message, sender: eventSender(), messageId: UUID().uuidString, date: Date())
        self.messageList.append(msg)

        self.messagesCollectionView.insertItemAfterLast()
        self.messagesCollectionView.scrollToBottom(animated: false)

    }
  
    
    @objc func loadMoreMessages() {
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: DispatchTime.now() + 4) {
            
        }
    }
    
    @objc func loadMessages(from conversation: Conversation) {
        self.cleanAllMessages(reload: false)
        
        DispatchQueue.global(qos: .userInitiated).async {
            if let set = conversation.messages {
                for m in set {
                    if let message = m as? Message {
                        var userID = conversation.connection != nil ? ConnectionsController.shared.usersController(forConnection: conversation.connection).user(withNick: message.nick!)?.userID : UInt32(message.userID)
                        
                        if message.me == true {
                            userID = 111111
                        }
                        
                        let sender = Sender(id: "\(userID ?? UInt32(message.userID))", displayName: message.nick!)
                        let msg = PrivateMessage(text: message.body!, sender: sender, messageId: UUID().uuidString, date: Date())

                        DispatchQueue.main.async {
                            self.messageList.append(msg)
                            self.messagesCollectionView.reloadData()

                            self.perform(#selector(self.scrollToBottom), with: nil, afterDelay: 0.1)
                        }
                    }
                }
            }
        }
    }
    
    
    @objc private func scrollToBottom() {
        self.messagesCollectionView.scrollToBottom(animated: false)
    }
    
  
    public func cleanAllMessages(reload:Bool = true) {
        messageList = []
        
        if reload {
            self.messagesCollectionView.reloadData()
        }
    }
}

// MARK: - MessagesDataSource

extension ConversationViewController: MessagesDataSource {
  
  func currentSender() -> Sender {
    let nick = UserDefaults.standard.string(forKey: "WSUserNick")
    return Sender(id: "111111", displayName: nick!)
  }
    
    func eventSender() -> Sender {
        return Sender(id: "000000", displayName: "")
    }

  func numberOfMessages(in messagesCollectionView: MessagesCollectionView) -> Int {
    return messageList.count
  }
  
  func messageForItem(at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> MessageType {
    return messageList[indexPath.section] as! MessageType
  }
  
  func cellTopLabelAttributedText(for message: MessageType, at indexPath: IndexPath) -> NSAttributedString? {
    
    if isFromCurrentSender(message: message) {
      return nil
    }
    
    let font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small))
    let color = NSColor.secondaryLabelColor
    let attributes: [NSAttributedString.Key : Any] = [.font : font, .foregroundColor: color]
    
    let name = message.sender.displayName
    return NSAttributedString(string: name, attributes: attributes)
  }
  
  func cellBottomLabelAttributedText(for message: MessageType, at indexPath: IndexPath) -> NSAttributedString? {
    
    if isFromCurrentSender(message: message) {
      
      let font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small))
      let color = NSColor.tertiaryLabelColor
      var attributes: [NSAttributedString.Key : Any] = [.font : font,
                                                        .foregroundColor: color]
      
      attributes[.toolTip] = formatter.string(from: message.sentDate)
      
      return NSAttributedString(string: "Sent", attributes: attributes)
    }
    
    return nil
    //      struct ConversationDateFormatter {
    //        static let formatter: DateFormatter = {
    //          let formatter = DateFormatter()
    //          formatter.dateStyle = .medium
    //          return formatter
    //        }()
    //      }
    //      let formatter = ConversationDateFormatter.formatter
    //      let dateString = formatter.string(from: message.sentDate)
    //      return NSAttributedString(string: dateString, attributes: [NSAttributedString.Key.font: NSFont.userFont(ofSize: 10)!])
  }
  
}

// MARK: - MessagesDisplayDelegate

extension ConversationViewController: MessagesDisplayDelegate {
  
  // MARK: - Text Messages
  
  func detectorAttributes(for detector: DetectorType, and message: MessageType, at indexPath: IndexPath) -> [NSAttributedString.Key : Any] {
    return MessageLabel.defaultAttributes
  }
  
  func enabledDetectors(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> [DetectorType] {
    return [.url, .address, .phoneNumber, .date]
  }
  
  // MARK: - All Messages
  
  func backgroundColor(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> NSColor {
    return isFromCurrentSender(message: message) ? message is ChatMessage ? NSColor(red: 69/255, green: 193/255, blue: 89/255, alpha: 1) : NSColor(red: 3/255, green: 106/255, blue: 221/255, alpha: 1) : NSColor(red: 230/255, green: 230/255, blue: 230/255, alpha: 1)
  }
    
    
    func textColor(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> NSColor? {
        if message is ChatMessage || message is PrivateMessage {
            return isFromCurrentSender(message: message) ? NSColor.white : NSColor.controlDarkShadowColor
        }
        
        return NSColor.textColor
    }
  
  func messageStyle(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> MessageStyle {
    if message is ChatMessage || message is PrivateMessage {
        let corner: MessageStyle.TailCorner = isFromCurrentSender(message: message) ? .bottomRight : .bottomLeft
        return .bubbleTail(corner, .curved)
    }
    else if message is EventMessage {
        return .custom { (view) in
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.clear.cgColor
        }
    }
    return .bubble
  }
  
  func configureAvatarView(_ avatarView: AvatarView, for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) {
    var avatar = Avatar(image: nil, initials: "?")

    if message is ChatMessage || message is PrivateMessage {
        if message.sender.id == "111111" {
            let archivedData = UserDefaults.standard.data(forKey: "WSUserIcon")
            let imageData = try! NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(archivedData!) as? Data
            let image = NSImage(data: imageData!)
            avatar = Avatar(image: image)
            
        } else {
            if let userId = UInt32(message.sender.id) {
                if self.connection != nil {
                    let uc = ConnectionsController.shared.usersController(forConnection: self.connection)
                    avatar = uc.getAvatar(forUserID: userId)
                }
            }
        }
    } else if message is EventMessage {
        avatar = Avatar(image: nil, initials: "SV")
    }
    
    avatarView.set(avatar: avatar)
    avatarView.layer?.backgroundColor = NSColor.clear.cgColor
    avatarView.cursor = NSCursor.pointingHand
  }
  
  func menu(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> NSMenu? {
    
    let menu = NSMenu(title: "Menu")
    
    let menuItem = NSMenuItem(title: "Do Something", action: nil, keyEquivalent: "")
    menu.addItem(menuItem)
    
    return menu
  }
  
}

// MARK: - MessagesLayoutDelegate

extension ConversationViewController: MessagesLayoutDelegate {
  
  func avatarPosition(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> AvatarPosition {
    return AvatarPosition(horizontal: .natural, vertical: .messageBottom)
  }
    
    
  
  func cellTopLabelAlignment(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> LabelAlignment {
    if isFromCurrentSender(message: message) {
      return .messageTrailing(NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 20))
    } else {
      return .messageLeading(NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 0))
    }
  }
  
  func cellBottomLabelAlignment(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> LabelAlignment {
    if isFromCurrentSender(message: message) {
      return .messageTrailing(NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 10))
    } else {
      return .messageLeading(NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 0))
    }
  }
  
  // MARK: - Location Messages
  
  func heightForLocation(message: MessageType, at indexPath: IndexPath, with maxWidth: CGFloat, in messagesCollectionView: MessagesCollectionView) -> CGFloat {
    return 200
  }
  
}

// MARK: - MessageCellDelegate

extension ConversationViewController: MessageItemDelegate {
  
  func didClickAvatar(in item: MessageCollectionViewItem) {
    guard let indexPath = messagesCollectionView.indexPath(for: item) else { return }
    let msg = messageForItem(at: indexPath, in: messagesCollectionView)
    print("Avatar clicked: \(msg.sender.id)")
  }
  
  func didClickMessage(in item: MessageCollectionViewItem) {
    print("Message clicked")
  }
  
}

// MARK: - MessageLabelDelegate

extension ConversationViewController: MessageLabelDelegate {
  
  func didSelectAddress(_ addressComponents: [String : String]) {
    print("Address Selected: \(addressComponents)")
  }
  
  func didSelectDate(_ date: Date) {
    print("Date Selected: \(date)")
  }
  
  func didSelectPhoneNumber(_ phoneNumber: String) {
    print("Phone Number Selected: \(phoneNumber)")
  }
  
  func didSelectURL(_ url: URL) {
    print("URL Selected: \(url)")
  }
  
}

// MARK: - MessageInputBarDelegate

extension ConversationViewController: MessageInputBarDelegate {
  
  func messageInputBar(_ inputBar: MessageInputBar, didPressSendButtonWith text: String) {
    
    // Each NSTextAttachment that contains an image will count as one empty character in the text: String
    
    for component in inputBar.inputTextView.components {
      
      if let image = component as? NSImage {
        
        let imageMessage = ChatMessage(image: image, sender: currentSender(), messageId: UUID().uuidString, date: Date())
        messageList.append(imageMessage)
        messagesCollectionView.insertSections([messageList.count - 1])
        
      } else if let text = component as? String {
        
        let attributedText = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.blue])
        
        let message = ChatMessage(attributedText: attributedText, sender: currentSender(), messageId: UUID().uuidString, date: Date())
        messageList.append(message)
        messagesCollectionView.insertSections([messageList.count - 1])
      }
      
    }
    
    inputBar.inputTextView.string = String()
    //        messagesCollectionView.scrollToBottom()
  }
}

