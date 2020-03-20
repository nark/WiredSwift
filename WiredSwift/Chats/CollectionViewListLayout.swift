//
//  CollectionViewListLayout.swift
//  money
//
//  Created by Robert Dougan on 29/09/15.
//  Copyright © 2015 Phyn3t. All rights reserved.
//

import Cocoa

class CollectionViewListLayout: NSCollectionViewLayout {

    var itemHeight: CGFloat = 100
    var verticalSpacing: CGFloat = 0
    var containerPadding: NSEdgeInsets = NSEdgeInsetsZero
    
    override var collectionViewContentSize: NSSize {
        get {
            let count = self.collectionView?.numberOfItems(inSection: 0)
            if (count == 0) {
                return NSZeroSize
            }
            
            var size = self.collectionView!.superview!.bounds.size
            size.height = (CGFloat(count!) * (self.itemHeight + self.verticalSpacing)) - self.verticalSpacing + self.containerPadding.top + self.containerPadding.bottom
            
            return size
        }
    }
    
    override func prepare() {
        super.prepare()
        
        
    }
    
    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        let count = self.collectionView?.numberOfItems(inSection: 0)
        if (count == 0) {
            return nil
        }
        
        if let item = self.collectionView?.item(at: indexPath) as? ChatMessageItem {
            self.itemHeight = item.messageLabel.sizeThatFits(self.collectionView!.frame.size).height
        }
        
        print("self.itemHeight : \(self.itemHeight)")
        
        let frame = NSMakeRect(self.containerPadding.left, self.containerPadding.top + ((self.itemHeight + self.verticalSpacing) * CGFloat(indexPath.item)), self.collectionViewContentSize.width - self.containerPadding.left - self.containerPadding.right, self.itemHeight)
        
        let itemAttributes = NSCollectionViewLayoutAttributes(forItemWith: indexPath as IndexPath)
        itemAttributes.frame = frame
        
        return itemAttributes
    }
    
    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        var attributes = [NSCollectionViewLayoutAttributes]()
        
        if let count = self.collectionView?.numberOfItems(inSection: 0), count > 0 {
            for index in 0...(count - 1) {
                let indexPath = NSIndexPath(forItem: index, inSection: 0)
                if let itemAttributes = self.layoutAttributesForItem(at: indexPath as IndexPath) {
                    attributes.append(itemAttributes)
                }
            }
        }
        
        return attributes
    }
    
    
    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        return true
    }
    
}
