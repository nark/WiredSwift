//
//  DetailViewController.swift
//  Wired iOS
//
//  Created by Rafael Warnault on 31/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import UIKit
import MessageKit
import InputBarAccessoryView
import WiredSwift_iOS





class ChatViewController: MessagesViewController {
    @IBOutlet var infoButton: UIBarButtonItem!
    
    var selfSender:Sender = Sender(senderId: "-1", displayName: "Wired iOS")
    var messages:[MessageType] = []
    var users:[UserInfo] = []
    var senders:[UInt32:Sender] = [:]
    var avatars:[UInt32:Avatar] = [:]
    var bookmark:Bookmark!
    
    var joined:Bool = false
    
    private var keyboardHelper: KeyboardHelper?
    
    open lazy var attachmentManager: AttachmentManager = { [unowned self] in
        let manager = AttachmentManager()
        manager.delegate = self
        return manager
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        NotificationCenter.default.addObserver(self, selector: #selector(userDidUpdateProfile(_:)), name: .userDidUpdateProfile, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(willTerminateNotification(_ :)), name: UIApplication.willTerminateNotification, object: nil)
        
        self.keyboardHelper = KeyboardHelper { [unowned self] animation, keyboardFrame, duration in
            switch animation {
            case .keyboardWillShow:
                self.messagesCollectionView.scrollToBottom()
            case .keyboardWillHide:
                self.messagesCollectionView.scrollToBottom()
            }
        }

        self.setupMessagesView()
        // disbaled for now
        // self.setupCameraButton()
            
        configureView()
    }
    

    var connection: Connection? {
        didSet {
            // Update the view.
            configureView()
            
            if let c = self.connection, c.isConnected() {
                if !joined {
                    c.addDelegate(self)
                    
                    self.selfSender = Sender(senderId: "\(self.connection!.userID!)", displayName: "Wired iOS")
                    
                    _ = c.joinChat(chatID: 1)
                }
            }
        }
    }


    
    
    // MARK: -
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "ShowServerInfo" {
            if let controller = segue.destination as? ServerInfoViewController {
                controller.users        = self.users
                controller.connection   = self.connection
            }
        }
    }
    
    
    // MARK: -
    @objc func popBack() {
        self.navigationController?.popToRootViewController(animated: true)
    }
    
    @objc func willTerminateNotification(_ n:Notification) {
        if self.connection != nil && self.connection!.isConnected() {
            self.connection!.disconnect()
            popBack()
        }
    }
    
    @objc func userDidUpdateProfile(_ n:Notification) {
        if self.connection != nil && self.connection!.isConnected() {
            var message = P7Message(withName: "wired.user.set_nick", spec: self.connection!.spec)
            
            if let nick = UserDefaults.standard.string(forKey: "WSUserNick") {
                message.addParameter(field: "wired.user.nick", value: nick)
            }
            
            _ = self.connection?.send(message: message)
            
            message = P7Message(withName: "wired.user.set_status", spec: self.connection!.spec)
            
            if let status = UserDefaults.standard.string(forKey: "WSUserStatus") {
                message.addParameter(field: "wired.user.status", value: status)
            }
            
            _ = self.connection?.send(message: message)
            
            message = P7Message(withName: "wired.user.set_icon", spec: self.connection!.spec)
            
            if let icon = UserDefaults.standard.image(forKey: "WSUserIcon")?.pngData() {
                message.addParameter(field: "wired.user.icon", value: icon)
            }
            
            _ = self.connection?.send(message: message)
        }
    }


    @objc func sendMessage() {
        // send pastboard image
        let stringWithoutAttachments:NSMutableAttributedString = NSMutableAttributedString(attributedString: messageInputBar.inputTextView.attributedText)
        
        // disable Text attachment for now
        messageInputBar.inputTextView.attributedText.enumerateAttribute(NSAttributedString.Key.attachment, in: NSRange(location: 0, length: messageInputBar.inputTextView.attributedText.length), options: [], using: {(value,range,_) -> Void in
            if (value is NSTextAttachment) {
//               let attachment: NSTextAttachment? = (value as? NSTextAttachment)
//               var image: UIImage?
//
//               if ((attachment?.image) != nil) {
//                   image = attachment?.image
//               } else {
//                   image = attachment?.image(forBounds: (attachment?.bounds)!, textContainer: nil, characterIndex: range.location)
//               }
//
//                guard let pasteImage = image?.scale(with: CGSize(width: 320, height: 320), ifNeeded: true) else { return }
//
//               guard let pngData = pasteImage.pngData() else { return }
//               //guard let pngImage = UIImage(data: pngData) else { return }
//
//               let base64String = pngData.base64EncodedString()
//               let htmlString = "<img src='data:image/png;base64,\(base64String)'/>"
//
//               let message = P7Message(withName: "wired.chat.send_say", spec: self.connection!.spec)
//               message.addParameter(field: "wired.chat.id", value: UInt32(1))
//               message.addParameter(field: "wired.user.id", value: UInt32(self.selfSender.senderId))
//               message.addParameter(field: "wired.chat.say", value: htmlString)
//
//               if self.connection!.send(message: message) {
//
//               }

                stringWithoutAttachments.deleteCharacters(in: range)
                // return
           }
        })
        
        // send text
        let text = stringWithoutAttachments.string

        if text.isBlank == false {
            if self.connection != nil && self.connection!.isConnected() {
                let message = P7Message(withName: "wired.chat.send_say", spec: self.connection!.spec)
                message.addParameter(field: "wired.chat.id", value: UInt32(1))
                message.addParameter(field: "wired.user.id", value: UInt32(self.selfSender.senderId))
                message.addParameter(field: "wired.chat.say", value: text)

                if self.connection!.send(message: message) {
                    
                }
            }
        }
        
        messageInputBar.inputTextView.text = ""
        
        
//        // send attachments
//        for attachment in self.attachmentManager.attachments {
//             switch attachment {
//             case .image(let image):
//                if let base64String = image.pngData()?.base64EncodedString() {
//                    let htmlString = "<img src='data:image/png;base64,\(base64String)'/>"
//
//                    let message = P7Message(withName: "wired.chat.send_say", spec: self.connection!.spec)
//                    message.addParameter(field: "wired.chat.id", value: UInt32(1))
//                    message.addParameter(field: "wired.user.id", value: UInt32(self.selfSender.senderId))
//                    message.addParameter(field: "wired.chat.say", value: htmlString)
//
//                    if self.connection!.send(message: message) {
//                        messageInputBar.inputTextView.text = ""
//                    }
//                }
//
//
//
//                break
//             default: break
//            }
//        }
//
//        // remove attachments
//        while self.attachmentManager.attachments.count > 0 {
//            self.attachmentManager.removeAttachment(at: 0)
//        }
//
//        // hide attachments
        setAttachmentManager(active: self.attachmentManager.attachments.count > 0)
    }


    // MARK: - Privates
    
    private func systemSender() -> Sender {
        return Sender(senderId: "-1", displayName: "")
    }

    
    private func configureView() {
        self.navigationItem.title = self.connection?.serverInfo.serverName
        
        if self.connection != nil && self.connection!.isConnected() {
            self.infoButton.isEnabled = true
            self.messageInputBar.isHidden = false
        } else {
            self.infoButton.isEnabled = false
            self.messageInputBar.isHidden = true
        }
    }

    
    
    private func setupMessagesView() {
        messagesCollectionView.contentInset = UIEdgeInsets(top: 44, left: 0, bottom: 0, right: 0)
        messagesCollectionView.messagesDataSource = self
        messagesCollectionView.messagesLayoutDelegate = self
        messagesCollectionView.messagesDisplayDelegate = self
        messagesCollectionView.messageCellDelegate = self
        
        if let layout = messagesCollectionView.collectionViewLayout as? MessagesCollectionViewFlowLayout {
            layout.textMessageSizeCalculator.outgoingAvatarSize = .zero
            layout.setMessageOutgoingAvatarSize(.zero)
        }
        
        messageInputBar.inputPlugins = [attachmentManager]
        messageInputBar.sendButton.addTarget(self, action: #selector(sendMessage), for: UIControl.Event.touchDown)
        messageInputBar.inputTextView.allowsEditingTextAttributes = false

        messageInputBar.sendButton.configure {
            $0.title = ""
            $0.image = UIImage(named: "Send")
        }
        
    }
    
    
        
    private func setupCameraButton() {
        let charCountButton = InputBarButtonItem()
        .configure {
            $0.image = UIImage(named: "Camera")?.withRenderingMode(.alwaysTemplate)
            $0.setSize(CGSize(width: 25, height: 35), animated: false)
            $0.contentHorizontalAlignment = .left
        }.onSelected { (item) in
            self.openCamera(item)
        }

        messageInputBar.setLeftStackViewWidthConstant(to: 50, animated: false)
        messageInputBar.setStackViewItems([charCountButton], forStack: .left, animated: false)
    }

    
    private func openCamera(_ sender:Any) {
//        let imagePicker = UIImagePickerController()
//        imagePicker.delegate = self
//
//
//        let alert = UIAlertController(title: NSLocalizedString("Photo"), message: NSLocalizedString("Select below"), preferredStyle: .actionSheet)
//
//        alert.popoverPresentationController?.sourceView = self.messageInputBar.contentView
//
//        alert.addAction(UIAlertAction(title: NSLocalizedString("Take Picture"), style: .default, handler: { (action) in
//            imagePicker.sourceType = .camera
//            (UIApplication.shared.delegate as? AppDelegate)?.window?.rootViewController?.present(imagePicker, animated: true, completion: nil)
//        }))
//
//        alert.addAction(UIAlertAction(title: NSLS("Photo Library"), style: .default, handler: { (action) in
//            imagePicker.sourceType = .photoLibrary
//            (UIApplication.shared.delegate as? AppDelegate)?.window?.rootViewController?.present(imagePicker, animated: true, completion: nil)
//        }))
//
//        alert.addAction(UIAlertAction(title: NSLS("Cancel"), style: .cancel, handler: nil))
//
//        self.navigationController?.present(alert, animated: true, completion: nil)
    }
    
    
    private struct ImageMediaItem: MediaItem {

        var url: URL?
        var image: UIImage?
        var placeholderImage: UIImage
        var size: CGSize

        init(image: UIImage) {
            self.image = image
            self.size = image.size
            self.placeholderImage = UIImage()
        }

    }
    
    
    private func append(base64Image string:String, sender: Sender, sent:Bool) {
        let uuid = UUID().uuidString
        
        if let data = Data(base64Encoded: string, options: .ignoreUnknownCharacters) {
            if let image = UIImage(data: data) {
                let mediaItem = ImageMediaItem(image: image)
                
                let message = ChatMessage(
                    sender: sender,
                    messageId: uuid,
                    sentDate: Date(),
                    kind: MessageKind.photo(mediaItem as MediaItem))
                
                self.messages.append(message)
                
                self.messagesCollectionView.reloadDataAndKeepOffset()
                self.messagesCollectionView.scrollToBottom()
            }
        }
    }
    
    
    private func append(textMessage text:String, sender: Sender, sent:Bool, event:Bool = false) {
        let uuid = UUID().uuidString
        let font = UIFont.systemFont(ofSize: event ? 14 : 17)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: sent ? UIColor.darkText : Style.Colors.label
        ]
        
        if !event {
            let message = ChatMessage(
                sender: sender,
                messageId: uuid,
                sentDate: Date(),
                kind: MessageKind.attributedText(NSAttributedString(string: text, attributes: attributes)))
            
            self.messages.append(message)
        } else {
            let message = EventMessage(
                    sender: sender,
                    messageId: uuid,
                    sentDate: Date(),
                    kind: MessageKind.attributedText(NSAttributedString(string: text, attributes: attributes)))
                
                self.messages.append(message)
        }
        
        self.messagesCollectionView.reloadDataAndKeepOffset()
        self.messagesCollectionView.scrollToBottom()
    }
    
    
    private func user(withID uid: UInt32) -> UserInfo? {
        for u in self.users {
            if uid == u.userID {
                return u
            }
        }
        return nil
    }
    
    private func removeUser(withID uid: UInt32) {
        var index = 0
        var remove:Int?
        
        for u in self.users {
            if uid == u.userID {
                remove = index
            }
            index += 1
        }
        
        
        if let i = remove {
            self.users.remove(at: i)
        }
    }
    
    
    // MARK: - AttachmentManagerDelegate Helper
    
    func setAttachmentManager(active: Bool) {
        let topStackView = messageInputBar.topStackView
        if active && !topStackView.arrangedSubviews.contains(attachmentManager.attachmentView) {
            topStackView.insertArrangedSubview(attachmentManager.attachmentView, at: topStackView.arrangedSubviews.count)
            topStackView.layoutIfNeeded()
        } else if !active && topStackView.arrangedSubviews.contains(attachmentManager.attachmentView) {
            topStackView.removeArrangedSubview(attachmentManager.attachmentView)
            topStackView.layoutIfNeeded()
            
            // Grrrr
//            messageInputBar.reloadInputViews()
//            messageInputBar.inputTextView.layoutIfNeeded()
//            messageInputBar.layoutStackViews()
//            messageInputBar.layoutIfNeeded()
        }
    }
    
    
    // MARK: - Helper function inserted by Swift 4.2 migrator.
    
    // Helper function inserted by Swift 4.2 migrator.
    fileprivate func convertFromUIImagePickerControllerInfoKeyDictionary(_ input: [UIImagePickerController.InfoKey: Any]) -> [String: Any] {
        return Dictionary(uniqueKeysWithValues: input.map {key, value in (key.rawValue, value)})
    }

    // Helper function inserted by Swift 4.2 migrator.
    fileprivate func convertFromUIImagePickerControllerInfoKey(_ input: UIImagePickerController.InfoKey) -> String {
        return input.rawValue
    }
}



// MARK: -

extension ChatViewController: ConnectionDelegate {
    func connectionDisconnected(connection: Connection, error: Error?) {
        configureView()
        
        let text = String(format: NSLocalizedString("You have beed disconnected from %@", comment: "Disconnected Alert Message"), bookmark.hostname!)
        
        self.append(textMessage: "<< \(text) >>", sender: self.systemSender(), sent: false, event: true)
                
        let alertController = UIAlertController(
            title: NSLocalizedString("Connection Error", comment: "Disconnected Alert Title"),
            message: text,
            preferredStyle: .alert)
        
        alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Disconnected Alert Button"), style: .default))
        

        self.present(alertController, animated: true) {
            self.navigationController?.popToRootViewController(animated: true)
        }
    }
    
    func connectionDidReceiveMessage(connection: Connection, message: P7Message) {
        if message.name == "wired.chat.say" || message.name == "wired.chat.me" {
            if let userID = message.uint32(forField: "wired.user.id") {
                let string = message.string(forField: "wired.chat.say") ?? message.string(forField: "wired.chat.me")
                
                let isSender = userID == self.connection?.userID
                
                if let s = string {
                    if let sender = self.senders[userID] {
                        if s.starts(with: "<img src='data:image/png;base64,") {
                            let base64String = s.dropFirst(32).dropLast(3)
                            self.append(base64Image: String(base64String), sender: sender, sent: isSender)
                            
                        } else {
                            self.append(textMessage: s, sender: sender, sent: isSender)
                        }
                    }
                }
            }
        }
        else if message.name == "wired.chat.user_list" {
            if  let userID = message.uint32(forField: "wired.user.id"),
                let iconData = message.data(forField: "wired.user.icon"),
                let nick = message.string(forField: "wired.user.nick") {
                
                self.users.append(UserInfo(message: message))
                self.senders[userID] = Sender(senderId: "\(userID)", displayName: nick)
                self.avatars[userID] = Avatar(image: UIImage(data: iconData), initials: nick)
            }
        }
        else if message.name == "wired.chat.user_list.done" {
            self.joined = true
        }
        else if message.name == "wired.chat.user_join" {
            if  let userID = message.uint32(forField: "wired.user.id"),
                let iconData = message.data(forField: "wired.user.icon"),
                let nick = message.string(forField: "wired.user.nick") {
                
                let isSender = userID == self.connection?.userID
                
                self.users.append(UserInfo(message: message))
                self.senders[userID] = Sender(senderId: "\(userID)", displayName: nick)
                self.avatars[userID] = Avatar(image: UIImage(data: iconData), initials: nick)
                
                if let sender = self.senders[userID] {
                    let text = String(format: NSLocalizedString("<< %@ joined the chat >>", comment: "User Joined Public Chat Event"), nick)
                    self.append(textMessage: text, sender: sender, sent: isSender, event: true)
                }
            }
        }
        else if message.name == "wired.chat.user_leave" {
            if  let userID = message.uint32(forField: "wired.user.id") {
                let isSender = userID == self.connection?.userID
                
                if let sender = self.senders[userID] {
                    let text = String(format: NSLocalizedString("<< %@ left the chat >>", comment: "User Leave Public Chat Event"), sender.displayName)
                    self.append(textMessage: text, sender: sender, sent: isSender, event: true)
                }
                
                self.removeUser(withID: userID)
                self.senders.removeValue(forKey: userID)
                //self.avatars.removeValue(forKey: userID)
            }
        }
        else if message.name == "wired.chat.user_status" ||
                message.name == "wired.chat.user_icon" {
            if  let userID = message.uint32(forField: "wired.user.id") {
                if let user = self.user(withID: userID) {
                    user.update(withMessage: message)
                    
                    self.senders[userID] = Sender(senderId: "\(userID)", displayName: user.nick!)
                    self.avatars[userID] = Avatar(image: UIImage(data: user.icon!), initials: user.nick!)
                }
            }
        }
        else if message.name == "wired.chat.topic" {
            if  let chatID = message.uint32(forField: "wired.chat.id"),
                let nick = message.string(forField: "wired.user.nick"),
                let topic = message.string(forField: "wired.chat.topic.topic"),
                let time = message.date(forField: "wired.chat.topic.time") {
                
                if chatID == 1 {
                    let text = String(format: NSLocalizedString("<< Topic: %@ by %@ on %@ >>", comment: "Public Chat Topic Changed Event"), topic, nick, AppDelegate.dateTimeFormatter.string(from: time))
                    self.append(textMessage: text, sender: self.systemSender(), sent: false, event: true)
                }
            }
        }
        else if message.name == "wired.chat.user_disconnect" {
            if let disconnectedID = message.uint32(forField: "wired.user.disconnected_id") {
                let disconnectMessage = message.string(forField: "wired.user.disconnect_message")
                
                if let user = self.user(withID: disconnectedID) {
                    var text = String(format: NSLocalizedString("<< %@ has been disconnected", comment: "Disconnected User Public Chat Event"), user.nick!)
                    
                    if disconnectMessage != nil && !disconnectMessage!.isEmpty {
                        text = text + String(format: NSLocalizedString(" with message: %@", comment: "Disconnected User Public Chat Message"), disconnectMessage!)
                    }
                    
                    text = text + " >>"
                    self.append(textMessage: text, sender: self.systemSender(), sent: false, event: true)
                }
            }
        }
        else if message.name == "wired.chat.user_kick" {
            if  let chatID = message.uint32(forField: "wired.chat.id"),
                let userID = message.uint32(forField: "wired.user.id"),
                let disconnectedID = message.uint32(forField: "wired.user.disconnected_id"){
                let disconnectMessage = message.string(forField: "wired.user.disconnect_message")
                
                if  let kickedUser = self.user(withID: disconnectedID),
                    let kickerUser = self.user(withID: userID),
                    chatID == 1 {
                    
                    var text = String(format: NSLocalizedString("<< %@ has been kicked by %@", comment: "Kicked User Public Chat Event"), kickedUser.nick!, kickerUser.nick!)
                    
                    if disconnectMessage != nil && !disconnectMessage!.isEmpty {
                        text = text + String(format: NSLocalizedString(" with message: %@", comment: "Kicked User Public Chat Message"), disconnectMessage!)
                    }
                    
                    text = text + " >>"
                    self.append(textMessage: text, sender: self.systemSender(), sent: false, event: true)
                }
            }
        }
        else if message.name == "wired.chat.user_ban" {
            if let disconnectedID = message.uint32(forField: "wired.user.disconnected_id") {
                let disconnectMessage = message.string(forField: "wired.user.disconnect_message")
                
                if let user = self.user(withID: disconnectedID) {
                    var text = String(format: NSLocalizedString("<< %@ has been banned", comment: "Banned User Public Chat Event"), user.nick!)
                    
                    if disconnectMessage != nil && !disconnectMessage!.isEmpty {
                        text = text + String(format: NSLocalizedString(" with message: %@", comment: "Banned User Public Chat Message"), disconnectMessage!)
                    }
                    
                    text = text + " >>"
                    self.append(textMessage: text, sender: self.systemSender(), sent: false, event: true)
                }
            }
        }
        else if message.name == "wired.message.message" {
            let response = P7Message(withName: "wired.message.send_message", spec: self.connection!.spec)
            
            if let userID = message.uint32(forField: "wired.user.id") {
                response.addParameter(field: "wired.user.id", value: userID)
                response.addParameter(field: "wired.message.message", value: NSLocalizedString("Not implemented yet, sorry. 🙂", comment: "Not implemented yet"))
                
                _ = self.connection!.send(message: response)
            }
        }
        
    }
    
    func connectionDidReceiveError(connection: Connection, message: P7Message) {

    }
}



// MARK: - UIImagePickerControllerDelegate

extension ChatViewController: UIImagePickerControllerDelegate & UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        // Local variable inserted by Swift 4.2 migrator.
        let info = convertFromUIImagePickerControllerInfoKeyDictionary(info)

        
        dismiss(animated: true, completion: {
            if let pickedImage = info[self.convertFromUIImagePickerControllerInfoKey(UIImagePickerController.InfoKey.originalImage)] as? UIImage {
                if let compressedImage = pickedImage.scale(with: CGSize(width: 420.0, height: 420.0)) {
                    let handled = self.attachmentManager.handleInput(of: compressedImage as AnyObject)
                    if !handled {
                        // throw error
                    }
                }
            }
        })
    }
}



// MARK: - MessageKit & InputBarAccessoryView

public enum DefaultStyle {
    public enum Colors {
        public static let label: UIColor = {
            if #available(iOS 13.0, *) {
                return UIColor.label
            } else {
                return .black
            }
        }()
    }
}

public let Style = DefaultStyle.self

public struct Sender: SenderType {
    public let senderId: String
    public let displayName: String
}

public struct ChatMessage : MessageType {
    public var sender: SenderType
    public var messageId: String
    public var sentDate: Date
    public var kind: MessageKind
}

public struct EventMessage : MessageType {
    public var sender: SenderType
    public var messageId: String
    public var sentDate: Date
    public var kind: MessageKind
}


extension ChatViewController: MessagesDisplayDelegate, MessagesLayoutDelegate {
    func configureAvatarView(_ avatarView: AvatarView, for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) {
        avatarView.backgroundColor = UIColor.clear
        avatarView.image = UIImage(named: "DefaultUser")
        
        if let userID = UInt32(message.sender.senderId) {
            if let avatar = self.avatars[userID] {
                avatarView.image = avatar.image
            }
        }
        
    }
    
    func enabledDetectors(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> [DetectorType] {
        return [.url]
    }

}



extension ChatViewController: MessagesDataSource {
    func currentSender() -> SenderType {
        return self.selfSender
    }
    
    func messageForItem(at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> MessageType {
        return messages[indexPath.section]
    }
    
    func numberOfSections(in messagesCollectionView: MessagesCollectionView) -> Int {
        return self.messages.count
    }
}


extension ChatViewController: MessageCellDelegate {
    func didSelectURL(_ url: URL) {
        UIApplication.shared.open(url)
    }
    
    func backgroundColor(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> UIColor {
        if message is EventMessage {
            return UIColor.clear
        }
        
        return self.messagesCollectionView.messagesDataSource!.isFromCurrentSender(message: message) ? UIColor.outgoingGreen : UIColor.incomingGray
    }
    
    func messageTopLabelHeight(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> CGFloat {
        if message is ChatMessage {
            if message.sender.senderId != self.currentSender().senderId {
                if message.sender.senderId != self.previous(forMessage: message)?.sender.senderId {
                    return 16.0
                }
            }
        }
        return 0
    }
    
    private func previous(forMessage message: MessageType) -> MessageType? {
        var previous:MessageType? = nil
        
        for m in self.messages {
            if previous != nil && m.messageId == message.messageId {
                return previous
            }
            
            previous = m
        }
        return nil
    }
    
    
    func messageTopLabelAttributedText(for message: MessageType, at indexPath: IndexPath) -> NSAttributedString? {
        if message is ChatMessage {
            if message.sender.senderId != self.currentSender().senderId {
                let attrs = [
                    NSAttributedString.Key.font: UIFont.systemFont(ofSize: 12.0),
                    NSAttributedString.Key.foregroundColor: UIColor.lightGray
                ]
                let attrString = NSAttributedString(string: message.sender.displayName, attributes: attrs)
                return attrString
            }
        }
        return nil
    }
}


extension ChatViewController : AttachmentManagerDelegate  {
    func attachmentManager(_ manager: AttachmentManager, shouldBecomeVisible: Bool) {
        //setAttachmentManager(active: shouldBecomeVisible)
    }
    
    func attachmentManager(_ manager: AttachmentManager, didRemove attachment: AttachmentManager.Attachment, at index: Int) {
        setAttachmentManager(active: manager.attachments.count > 0)
        messageInputBar.sendButton.isEnabled = manager.attachments.count > 0
    }
    
    func attachmentManager(_ manager: AttachmentManager, didReloadTo attachments: [AttachmentManager.Attachment]) {
        messageInputBar.sendButton.isEnabled = manager.attachments.count > 0
    }
    
    func attachmentManager(_ manager: AttachmentManager, didInsert attachment: AttachmentManager.Attachment, at index: Int) {
        setAttachmentManager(active: true)
        messageInputBar.sendButton.isEnabled = manager.attachments.count > 0
    }
}
