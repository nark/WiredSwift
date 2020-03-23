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

open class MediaMessageItem: MessageCollectionViewItem {
  
  open override class func reuseIdentifier() -> NSUserInterfaceItemIdentifier {
    return NSUserInterfaceItemIdentifier("messagekit.cell.mediamessage")
  }
  
  public required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  public override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
    super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
  }
  
  open override func loadView() {
    super.loadView()
  }
  
  // MARK: - Properties
  
  open lazy var playButtonView: PlayButtonView = {
    let playButtonView = PlayButtonView()
    return playButtonView
  }()
  
  // MARK: - Methods
  
  open func setupConstraints() {
    imageView?.fillSuperview()
    playButtonView.centerInSuperview()
    playButtonView.constraint(equalTo: CGSize(width: 35, height: 35))
  }
  
  open override func setupSubviews() {
    super.setupSubviews()
    
    let imageView = NSImageView()
    self.imageView = imageView
    messageContainerView.addSubview(imageView)
    messageContainerView.addSubview(playButtonView)
    setupConstraints()
  }
  
  open override func prepareForReuse() {
    super.prepareForReuse()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    imageView?.layer?.contents = nil
    CATransaction.commit()
  }
  
  open override func configure(with message: MessageType, at indexPath: IndexPath, and messagesCollectionView: MessagesCollectionView) {
    super.configure(with: message, at: indexPath, and: messagesCollectionView)
    switch message.data {
    case .photo(let image):
      imageView?.image = image
      imageView?.imageFrameStyle = .photo
      imageView?.imageScaling = .scaleProportionallyUpOrDown
      playButtonView.isHidden = true
    case .video(_, let image):
      imageView?.image = image
      imageView?.imageFrameStyle = .photo
      imageView?.imageScaling = .scaleProportionallyUpOrDown
      playButtonView.isHidden = false
    default:
      break
    }
  }
}
