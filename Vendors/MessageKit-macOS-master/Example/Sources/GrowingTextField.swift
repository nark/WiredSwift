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

class GrowingTextField: NSTextField {
  
  var minHeight: CGFloat? = 22
  let bottomSpace: CGFloat = 7
  // magic number! (the field editor TextView is offset within the NSTextField. It’s easy to get the space above (it’s origin), but it’s difficult to get the default spacing for the bottom, as we may be changing the height
  
  var heightLimit: CGFloat?
  var lastSize: NSSize?
  var isEditing = false
  
  override func textDidBeginEditing(_ notification: Notification) {
    super.textDidBeginEditing(notification)
    isEditing = true
  }
  override func textDidEndEditing(_ notification: Notification) {
    super.textDidEndEditing(notification)
    isEditing = false
  }
  override func textDidChange(_ notification: Notification) {
    super.textDidChange(notification)
    self.invalidateIntrinsicContentSize()
  }
  
  override var intrinsicContentSize: NSSize {
    var minSize: NSSize {
      var size = super.intrinsicContentSize
      size.height = minHeight ?? 0
      return size
    }
    // Only update the size if we’re editing the text, or if we’ve not set it yet
    // If we try and update it while another text field is selected, it may shrink back down to only the size of one line (for some reason?)
    if isEditing || lastSize == nil {
      
      //If we’re being edited, get the shared NSTextView field editor, so we can get more info
      guard let textView = self.window?.fieldEditor(false, for: self) as? NSTextView, let container = textView.textContainer, let newHeight = container.layoutManager?.usedRect(for: container).height
        else {
          return lastSize ?? minSize
      }
      var newSize = super.intrinsicContentSize
      newSize.height = newHeight + bottomSpace
      
      if let heightLimit = heightLimit, let lastSize = lastSize, newSize.height > heightLimit {
        newSize = lastSize
      }
      
      if let minHeight = minHeight, newSize.height < minHeight {
        newSize.height = minHeight
      }
      
      lastSize = newSize
      return newSize
    }
    else {
      return lastSize ?? minSize
    }
  }
  
}
