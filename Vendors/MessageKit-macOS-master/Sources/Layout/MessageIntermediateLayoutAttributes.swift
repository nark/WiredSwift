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

import Foundation

/// A intermediate context used to store recently calculated values used by
/// the `MessagesCollectionViewFlowLayout` object to reduce redundant calculations.
final class MessageIntermediateLayoutAttributes {

    // Message
    var message: MessageType
    var indexPath: IndexPath
    
    // Cell
    var itemHeight: CGFloat = 0
    var cellFrame: CGRect = .zero

    // AvatarView
    var avatarPosition = AvatarPosition(horizontal: .cellLeading, vertical: .cellBottom)
    var avatarSize: CGSize = .zero
    
    lazy var avatarFrame: CGRect = {
        
        guard avatarSize != .zero else { return .zero }
        
        var origin = CGPoint.zero
        
        switch avatarPosition.horizontal {
        case .cellLeading:
            break
        case .cellTrailing:
            origin.x = cellFrame.width - avatarSize.width
        case .natural:
            fatalError(MessageKitError.avatarPositionUnresolved)
        }
        
        switch avatarPosition.vertical {
        case .cellTop:
            origin.y = cellFrame.height - avatarSize.height
        case .cellBottom:
            break
        case .messageTop:
            origin.y = messageContainerFrame.maxY - avatarSize.height
        case .messageBottom:
            origin.y = messageContainerFrame.minY
        case .messageCenter:
            origin.y = messageContainerFrame.midY - (avatarSize.height/2)
        }
        
        return CGRect(origin: origin, size: avatarSize)
        
    }()

    // MessageContainerView
    var messageContainerSize: CGSize = .zero
    var messageContainerMaxWidth: CGFloat = 0
    var messageContainerPadding: NSEdgeInsets = NSEdgeInsetsZero
    var messageLabelInsets: NSEdgeInsets = NSEdgeInsetsZero
    
    lazy var messageContainerFrame: CGRect = {
        
        guard messageContainerSize != .zero else { return .zero }
        
        var origin: CGPoint = .zero
        origin.y = bottomLabelSize.height + messageContainerPadding.bottom + bottomLabelPadding.vertical
        
        switch avatarPosition.horizontal {
        case .cellLeading:
            origin.x = avatarSize.width + messageContainerPadding.left
        case .cellTrailing:
            origin.x = cellFrame.width - avatarSize.width - messageContainerSize.width - messageContainerPadding.right
        case .natural:
            fatalError(MessageKitError.avatarPositionUnresolved)
        }
        
        return CGRect(origin: origin, size: messageContainerSize)
        
    }()
    
    // Cell Top Label
    var topLabelAlignment: LabelAlignment = .cellLeading(NSEdgeInsetsZero)
    var topLabelSize: CGSize = .zero
    var topLabelMaxWidth: CGFloat = 0
    
    lazy var topLabelFrame: CGRect = {
        
        guard topLabelSize != .zero else { return .zero }
        
        var origin = CGPoint.zero
        
        origin.y = messageContainerFrame.maxY + topLabelPadding.bottom
        
        switch topLabelAlignment {
        case .cellLeading:
            origin.x = topLabelPadding.left
        case .cellCenter:
            origin.x = (cellFrame.width/2) + topLabelPadding.left - topLabelPadding.right
        case .cellTrailing:
            origin.x = cellFrame.width - topLabelSize.width - topLabelPadding.right
        case .messageLeading:
            origin.x = messageContainerFrame.minX + topLabelPadding.left
        case .messageTrailing:
            origin.x = messageContainerFrame.maxX - topLabelSize.width - topLabelPadding.right
        }
        
        return CGRect(origin: origin, size: topLabelSize)
        
    }()

    // Cell Bottom Label
    var bottomLabelAlignment: LabelAlignment = .cellTrailing(NSEdgeInsetsZero)
    var bottomLabelSize: CGSize = .zero
    var bottomLabelMaxWidth: CGFloat = 0
    
    lazy var bottomLabelFrame: CGRect = {
        
        guard bottomLabelSize != .zero else { return .zero }
        
        var origin: CGPoint = .zero
        
        origin.y = messageContainerFrame.minY - bottomLabelSize.height - bottomLabelPadding.top
        
        switch bottomLabelAlignment {
        case .cellLeading:
            origin.x = bottomLabelPadding.left
        case .cellCenter:
            origin.x = (cellFrame.width/2) + bottomLabelPadding.left - bottomLabelPadding.right
        case .cellTrailing:
            origin.x = cellFrame.width - bottomLabelSize.width - bottomLabelPadding.right
        case .messageLeading:
            origin.x = messageContainerFrame.minX + bottomLabelPadding.left
        case .messageTrailing:
            origin.x = messageContainerFrame.maxX - bottomLabelSize.width - bottomLabelPadding.right
        }
        
        return CGRect(origin: origin, size: bottomLabelSize)

    }()
    
    // MARK: - Initializer
    
    init(message: MessageType, indexPath: IndexPath) {
        self.message = message
        self.indexPath = indexPath
    }

}

// MARK: - Helpers

extension MessageIntermediateLayoutAttributes {
    
    var bottomLabelPadding: NSEdgeInsets {
        return bottomLabelAlignment.insets
    }

    var topLabelPadding: NSEdgeInsets {
        return topLabelAlignment.insets
    }

}
