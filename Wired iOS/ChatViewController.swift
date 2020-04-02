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

public struct Message : MessageType {
    public var sender: SenderType
    
    public var messageId: String
    
    public var sentDate: Date
    
    public var kind: MessageKind
}

extension ChatViewController: MessagesDisplayDelegate, MessagesLayoutDelegate {
    func configureAvatarView(_ avatarView: AvatarView, for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) {
        if let userID = UInt32(message.sender.senderId) {
            if let avatar = self.avatars[userID] {
                avatarView.backgroundColor = UIColor.clear
                avatarView.image = avatar.image
            }
        }
    }
    
    func enabledDetectors(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> [DetectorType] {
        return [.url]
    }
    
//    func messageTopLabelAttributedText(for message: MessageType, at indexPath: IndexPath) -> NSAttributedString? {
//        <#code#>
//    }
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
}


extension ChatViewController : AttachmentManagerDelegate {
    func attachmentManager(_ manager: AttachmentManager, shouldBecomeVisible: Bool) {

    }
    
    
}



class ChatViewController: MessagesViewController, ConnectionDelegate, UIImagePickerControllerDelegate & UINavigationControllerDelegate {
    @IBOutlet var infoButton: UIBarButtonItem!
    
    var selfSender:Sender = Sender(senderId: "-1", displayName: "Nark iOS")
    var messages:[MessageType] = []
    var users:[UserInfo] = []
    var senders:[UInt32:Sender] = [:]
    var avatars:[UInt32:Avatar] = [:]
    var bookmark:Bookmark!
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        NotificationCenter.default.addObserver(self, selector: #selector(userDidUpdateProfile(_:)), name: .userDidUpdateProfile, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(willTerminateNotification(_ :)), name: UIApplication.willTerminateNotification, object: nil)

        messagesCollectionView.contentInset = UIEdgeInsets(top: 44, left: 0, bottom: 0, right: 0)
        
        messagesCollectionView.messagesDataSource = self
        messagesCollectionView.messagesLayoutDelegate = self
        messagesCollectionView.messagesDisplayDelegate = self
        messagesCollectionView.messageCellDelegate = self
        

        let charCountButton = InputBarButtonItem()
        .configure {
            $0.image = UIImage(named: "Camera")?.withRenderingMode(.alwaysTemplate)
            $0.setSize(CGSize(width: 25, height: 35), animated: false)
            $0.contentHorizontalAlignment = .left
        }.onSelected { (item) in
            self.openCamera(item)
        }

        messageInputBar.setLeftStackViewWidthConstant(to: 40, animated: false)
        messageInputBar.setStackViewItems([charCountButton], forStack: .left, animated: false)
  
        messageInputBar.sendButton.addTarget(self, action: #selector(sendMessage), for: UIControl.Event.touchDown)
        
        configureView()
    }
    
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        if let c = self.connection {
            if c.isConnected() {
                //c.disconnect()
            }
        }
    }

    var connection: Connection? {
        didSet {
            // Update the view.
            configureView()
            
            if let c = self.connection {
                if c.isConnected() {
                    c.addDelegate(self)
                    
                    self.selfSender = Sender(senderId: "\(self.connection!.userID!)", displayName: "Wired iOS")
                    
                    _ = c.joinChat(chatID: 1)
                }
            }
        }
    }
    
    
    func configureView() {
        self.navigationItem.title = self.connection?.serverInfo.serverName
        
        if self.connection != nil && self.connection!.isConnected() {
            self.infoButton.isEnabled = true
            self.messageInputBar.isHidden = false
        } else {
            self.infoButton.isEnabled = false
            self.messageInputBar.isHidden = true
        }
    }

    
    func openCamera(_ sender:Any) {
        let imagePicker = UIImagePickerController()
        imagePicker.delegate = self
        
        
        let alert = UIAlertController(title: "Photo", message: "Select below", preferredStyle: .actionSheet)
        
        alert.popoverPresentationController?.sourceView = self.messageInputBar.contentView
        
        alert.addAction(UIAlertAction(title: "Take Picture", style: .default, handler: { (action) in
            imagePicker.sourceType = .camera
            (UIApplication.shared.delegate as? AppDelegate)?.window?.rootViewController?.present(imagePicker, animated: true, completion: nil)
        }))
        
        alert.addAction(UIAlertAction(title: "Photo Library", style: .default, handler: { (action) in
            imagePicker.sourceType = .photoLibrary
            (UIApplication.shared.delegate as? AppDelegate)?.window?.rootViewController?.present(imagePicker, animated: true, completion: nil)
        }))
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { (action) in }))
        
        self.navigationController?.present(alert, animated: true, completion: {
            
        })
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
    
    
    // MARK: -
    
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
    
    
    // MARK: -
    
    @objc func sendMessage() {
        if let text = messageInputBar.inputTextView.text {
            if self.connection != nil && self.connection!.isConnected() {
                let message = P7Message(withName: "wired.chat.send_say", spec: self.connection!.spec)
                message.addParameter(field: "wired.chat.id", value: UInt32(1))
                message.addParameter(field: "wired.user.id", value: UInt32(self.selfSender.senderId))
                message.addParameter(field: "wired.chat.say", value: text)
                
                if self.connection!.send(message: message) {
                    messageInputBar.inputTextView.text = ""
                }
            }
        }
    }

    
    // MARK: -
    func connectionDisconnected(connection: Connection, error: Error?) {
        configureView()
                
        let alertController = UIAlertController(
            title: "Connection Error",
            message: "You have beed disconnected from \(bookmark.hostname!)",
            preferredStyle: .alert)
        
        alertController.addAction(UIAlertAction(title: "OK", style: .default))

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
                    let uuid = UUID().uuidString
                    if let sender = self.senders[userID] {
                        let font = UIFont.systemFont(ofSize: 17)
                        let attributes: [NSAttributedString.Key: Any] = [
                            .font: font,
                            .foregroundColor: isSender ? UIColor.darkText : Style.Colors.label
                        ]
                        
                        let message = Message(
                            sender: sender,
                            messageId: uuid,
                            sentDate: Date(),
                            kind: MessageKind.attributedText(NSAttributedString(string: s, attributes: attributes)))
                        
                        self.messages.append(message)
                        
                        self.messagesCollectionView.reloadDataAndKeepOffset()
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
        else if message.name == "wired.message.message" {
            let response = P7Message(withName: "wired.message.send_message", spec: self.connection!.spec)
            
            if let userID = message.uint32(forField: "wired.user.id") {
                response.addParameter(field: "wired.user.id", value: userID)
                response.addParameter(field: "wired.message.message", value: "Not implemented yet, sorry. 🙂")
                
                _ = self.connection!.send(message: response)
            }
        }
    }
    
    func connectionDidReceiveError(connection: Connection, message: P7Message) {

    }
    
}
