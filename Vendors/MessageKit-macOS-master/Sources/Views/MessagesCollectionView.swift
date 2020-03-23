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

open class MessagesCollectionView: NSCollectionView {
  
  // MARK: - Properties
  
  open weak var messagesDataSource: MessagesDataSource?
  
  open weak var messagesDisplayDelegate: MessagesDisplayDelegate?
  
  open weak var messagesLayoutDelegate: MessagesLayoutDelegate?
  
  open weak var messageCellDelegate: MessageItemDelegate?
  
  open var showsDateHeaderAfterTimeInterval: TimeInterval = 3600
  
  open override var frame: NSRect {
    didSet {
      collectionViewLayout?.invalidateLayout()
    }
  }

  
  // MARK: - Initializers
  
  public override init(frame: CGRect) {
    super.init(frame: frame)
    wantsLayer = true
    //layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
    
    collectionViewLayout = MessagesCollectionViewFlowLayout()
    
    autoresizingMask = [.width, .height]
  }
  
  required public init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  public convenience init() {
    self.init(frame: .zero)
  }
  
  // MARK: - Methods

  var lastIndexPath: IndexPath {
    let lastSection = numberOfSections - 1
    return IndexPath(item: numberOfItems(inSection: lastSection) - 1,
                     section: lastSection)
  }
  
  
  @objc public func insertItemAfterLast() {
    insertSections([numberOfSections])
  }
  
  func isIndexPathAvailable(_ indexPath: IndexPath) -> Bool {
    guard dataSource != nil,
      indexPath.section >= 0,
      indexPath.item >= 0,
      indexPath.section < numberOfSections,
      indexPath.item < numberOfItems(inSection: indexPath.section) else {
        return false
    }
    
    return true
  }
  
  func scrollToItemIfAvailable(at indexPath: IndexPath, at scrollPosition:
    NSCollectionView.ScrollPosition, animated: Bool) {
    guard isIndexPathAvailable(indexPath) else { return }
    
    scrollToItem(at: indexPath, at: scrollPosition, animated: animated)
  }
  
  public func scrollToBottom(animated: Bool) {
    scrollToItemIfAvailable(at: lastIndexPath, at: NSCollectionView.ScrollPosition.bottom, animated: animated)
  }
  
  func scrollToItem(at indexPath: IndexPath,
                    at scrollPosition: NSCollectionView.ScrollPosition,
                    animated: Bool) {
    let indexes: Set<IndexPath> = [indexPath]
    if animated {
      self.animator().scrollToItems(at: indexes, scrollPosition: scrollPosition)
    } else {
      self.scrollToItems(at: indexes, scrollPosition: scrollPosition)
    }
  }

}
