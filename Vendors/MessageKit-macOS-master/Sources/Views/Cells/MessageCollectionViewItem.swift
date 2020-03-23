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

open class MessageCollectionViewItem: NSCollectionViewItem, CollectionViewReusable {
  
  open class func reuseIdentifier() -> NSUserInterfaceItemIdentifier {
    return NSUserInterfaceItemIdentifier("messagekit.cell.base-cell")
  }
  
  open var avatarView = AvatarView()
  
  open var messageContainerView: MessageContainerView = {
    let view = MessageContainerView()
    view.wantsLayer = true
    view.layer?.masksToBounds = true
    return view
  }()
  
  open var cellTopLabel = Label()
  
  open var cellBottomLabel = Label()
  
  open weak var delegate: MessageItemDelegate?
  
  open override func loadView() {
    view = NSView()
    view.postsFrameChangedNotifications = false
    view.postsBoundsChangedNotifications = false
    view.autoresizingMask = [.width, .height]
    view.wantsLayer = true
    setupSubviews()
  }
  
  open func setupSubviews() {
    view.addSubview(messageContainerView)
    view.addSubview(avatarView)
    view.addSubview(cellTopLabel)
    view.addSubview(cellBottomLabel)
  }
  
  open override func prepareForReuse() {
    super.prepareForReuse()
    avatarView.prepareForReuse()
    cellTopLabel.string = ""
    cellBottomLabel.string = ""
  }
  
  // MARK: - Configuration
  
  open override func apply(_ layoutAttributes: NSCollectionViewLayoutAttributes) {
    super.apply(layoutAttributes)
    if let attributes = layoutAttributes as? MessagesCollectionViewLayoutAttributes {
      avatarView.frame = attributes.avatarFrame
      cellTopLabel.frame = attributes.topLabelFrame
      cellBottomLabel.frame = attributes.bottomLabelFrame
      messageContainerView.frame = attributes.messageContainerFrame
    }
  }
  
  open func configure(with message: MessageType, at indexPath: IndexPath, and messagesCollectionView: MessagesCollectionView) {
    guard let dataSource = messagesCollectionView.messagesDataSource else {
      fatalError(MessageKitError.nilMessagesDataSource)
    }
    guard let displayDelegate = messagesCollectionView.messagesDisplayDelegate else {
      fatalError(MessageKitError.nilMessagesDisplayDelegate)
    }
    
    delegate = messagesCollectionView.messageCellDelegate
    
    let messageColor = displayDelegate.backgroundColor(for: message, at: indexPath, in: messagesCollectionView)
    let messageStyle = displayDelegate.messageStyle(for: message, at: indexPath, in: messagesCollectionView)
    
    displayDelegate.configureAvatarView(avatarView, for: message, at: indexPath, in: messagesCollectionView)
    
    messageContainerView.layer?.backgroundColor = messageColor.cgColor
    messageContainerView.style = messageStyle
    
    let topText = dataSource.cellTopLabelAttributedText(for: message, at: indexPath)
    let bottomText = dataSource.cellBottomLabelAttributedText(for: message, at: indexPath)
    
    cellTopLabel.attributedStringValue = topText ?? NSAttributedString()
    cellBottomLabel.attributedStringValue = bottomText  ?? NSAttributedString()
    
    avatarView.target = self
    avatarView.action = #selector(didClickAvatar)
    
  }
  
  @objc public func didClickAvatar() {
    delegate?.didClickAvatar(in: self)
  }
  
}
