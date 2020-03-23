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

open class Label: NSTextView {
  
  internal lazy var rangesForDetectors: [DetectorType: [(NSRange, MessageTextCheckingType)]] = [:]
  
  open weak var labelDelegate: MessageLabelDelegate?
  
  public override init(frame: CGRect) {
    super.init(frame: frame)
  }
  
  public override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
    super.init(frame: frameRect, textContainer: container)
    self.translatesAutoresizingMaskIntoConstraints = false
    self.autoresizingMask = .none
    self.textContainerInset = NSZeroSize
    self.drawsBackground = false
    self.isEditable = false
    self.isSelectable = true
    self.postsBoundsChangedNotifications = false
    
    if let textContainer = self.textContainer {
      textContainer.maximumNumberOfLines = 0
      textContainer.lineFragmentPadding = 0
    }

  }
  
  convenience init() {
    self.init(frame: NSZeroRect)
  }
  
  public required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  open override func clicked(onLink link: Any, at charIndex: Int) {
    if link is NSURL {
      super.clicked(onLink: link, at: charIndex)
      return
    }
    
    for (detectorType, ranges) in rangesForDetectors {
      for (range, value) in ranges {
        if range.contains(charIndex) {
          handleClicked(for: detectorType, value: value)
        }
      }
    }
  }

  public var attributedStringValue: NSAttributedString {
    get {
      return self.attributedString()
    }
    
    set {
      let newTextStorage = NSTextStorage(attributedString: newValue)
      layoutManager?.replaceTextStorage(newTextStorage)
    }
  }
  
  private func handleClicked(for detectorType: DetectorType, value: MessageTextCheckingType) {
    
    switch value {
    case let .addressComponents(addressComponents):
      var transformedAddressComponents = [String: String]()
      guard let addressComponents = addressComponents else { return }
      addressComponents.forEach { (key, value) in
        transformedAddressComponents[key.rawValue] = value
      }
      handleAddress(transformedAddressComponents)
    case let .phoneNumber(phoneNumber):
      guard let phoneNumber = phoneNumber else { return }
      handlePhoneNumber(phoneNumber)
    case let .date(date):
      guard let date = date else { return }
      handleDate(date)
    case let .link(url):
      guard let url = url else { return }
      handleURL(url)
    }
  }
    
  private func handleAddress(_ addressComponents: [String: String]) {
    labelDelegate?.didSelectAddress(addressComponents)
  }
  
  private func handleDate(_ date: Date) {
    labelDelegate?.didSelectDate(date)
  }
  
  private func handleURL(_ url: URL) {
    labelDelegate?.didSelectURL(url)
  }
  
  private func handlePhoneNumber(_ phoneNumber: String) {
    labelDelegate?.didSelectPhoneNumber(phoneNumber)
  }
  
}


public enum MessageTextCheckingType {
  case addressComponents([NSTextCheckingKey: String]?)
  case date(Date?)
  case phoneNumber(String?)
  case link(URL?)
}
