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
  
  var messageList: [MockMessage] = []
  
  var isTyping = false
  
  let formatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    return formatter
  }()
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    let messagesToFetch = UserDefaults.standard.mockMessagesCount()
    
    DispatchQueue.global(qos: .userInitiated).async {
      SampleData.shared.getMessages(count: 500) { messages in
        DispatchQueue.main.async {
          self.messageList = messages
          self.messagesCollectionView.reloadData()
          //self.messagesCollectionView.scrollToBottom()
        }
      }
    }
    
    messagesCollectionView.messagesDataSource = self
    messagesCollectionView.messagesLayoutDelegate = self
    messagesCollectionView.messagesDisplayDelegate = self
    messagesCollectionView.messageCellDelegate = self
    //        messageInputBar.delegate = self
    
    //messageInputBar.sendButton.tintColor = UIColor(red: 69/255, green: 193/255, blue: 89/255, alpha: 1)
    scrollsToBottomOnKeybordBeginsEditing = true // default false
    maintainPositionOnKeyboardFrameChanged = true // default false
    
    
  }
  
  func addMessage(message: String) {
    
    let msg = MockMessage(text: message, sender: currentSender(), messageId: UUID().uuidString, date: Date())
    self.messageList.append(msg)
    
    self.messagesCollectionView.insertItemAfterLast()
    self.messagesCollectionView.scrollToBottom(animated: false)
    
  }
  
  @objc func loadMoreMessages() {
    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: DispatchTime.now() + 4) {
      SampleData.shared.getMessages(count: 10) { messages in
        DispatchQueue.main.async {
          self.messageList.insert(contentsOf: messages, at: 0)
          //                    self.messagesCollectionView.reloadDataAndKeepOffset()
        }
      }
    }
  }
  
  
}

// MARK: - MessagesDataSource

extension ConversationViewController: MessagesDataSource {
  
  func currentSender() -> Sender {
    return SampleData.shared.currentSender
  }
  
  func numberOfMessages(in messagesCollectionView: MessagesCollectionView) -> Int {
    return messageList.count
  }
  
  func messageForItem(at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> MessageType {
    return messageList[indexPath.section]
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
  
  //  func textColor(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> NSColor {
  //    return isFromCurrentSender(message: message) ? NSColor.white : NSColor.controlDarkShadowColor
  //  }
  
  func detectorAttributes(for detector: DetectorType, and message: MessageType, at indexPath: IndexPath) -> [NSAttributedString.Key : Any] {
    return MessageLabel.defaultAttributes
  }
  
  func enabledDetectors(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> [DetectorType] {
    return [.url, .address, .phoneNumber, .date]
  }
  
  // MARK: - All Messages
  
  func backgroundColor(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> NSColor {
    return isFromCurrentSender(message: message) ? NSColor(red: 69/255, green: 193/255, blue: 89/255, alpha: 1) : NSColor(red: 230/255, green: 230/255, blue: 230/255, alpha: 1)
  }
  
  func messageStyle(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> MessageStyle {
    let corner: MessageStyle.TailCorner = isFromCurrentSender(message: message) ? .bottomRight : .bottomLeft
    return .bubbleTail(corner, .curved)
  }
  
  func configureAvatarView(_ avatarView: AvatarView, for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) {
    let avatar = SampleData.shared.getAvatarFor(sender: message.sender)
    avatarView.set(avatar: avatar)
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
        
        let imageMessage = MockMessage(image: image, sender: currentSender(), messageId: UUID().uuidString, date: Date())
        messageList.append(imageMessage)
        messagesCollectionView.insertSections([messageList.count - 1])
        
      } else if let text = component as? String {
        
        let attributedText = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.blue])
        
        let message = MockMessage(attributedText: attributedText, sender: currentSender(), messageId: UUID().uuidString, date: Date())
        messageList.append(message)
        messagesCollectionView.insertSections([messageList.count - 1])
      }
      
    }
    
    inputBar.inputTextView.string = String()
    //        messagesCollectionView.scrollToBottom()
  }
  
}

