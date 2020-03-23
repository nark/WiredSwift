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

open class AvatarView: NSImageView {
  
  // MARK: - Properties
  
  open var initials: String? {
    didSet {
      setImageFrom(initials: initials)
    }
  }
  
  open var placeholderFont: NSFont = NSFont.preferredFont(forTextStyle: .caption1) {
    didSet {
      setImageFrom(initials: initials)
    }
  }
  
  open var placeholderTextColor: NSColor = NSColor.white {
    didSet {
      setImageFrom(initials: initials)
    }
  }
  
  open var fontMinimumScaleFactor: CGFloat = 0.5
  
  open var adjustsFontSizeToFitWidth = true
  
  open var cursor: NSCursor?
  
  private var minimumFontSize: CGFloat {
    return placeholderFont.pointSize * fontMinimumScaleFactor
  }
  
  private var radius: CGFloat?
  
  // MARK: - Overridden Properties
  open override var frame: CGRect {
    didSet {
      setCorner(radius: self.radius)
    }
  }
  
  open override var bounds: CGRect {
    didSet {
      setCorner(radius: self.radius)
    }
  }
  
  // MARK: - Initializers
  public override init(frame: CGRect) {
    super.init(frame: frame)
    prepareView()
  }
  
  convenience public init() {
    self.init(frame: .zero)
  }
  
  private func setImageFrom(initials: String?) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    guard let initials = initials else { return }
    image = getImageFrom(initials: initials)
    self.layer?.contents = image
    CATransaction.commit()
  }
  
  private func getImageFrom(initials: String) -> NSImage {
    let width = frame.width
    let height = frame.height
    if width == 0 || height == 0 {return NSImage()}
    var font = placeholderFont
    
    //// Text Drawing
    let textRect = calculateTextRect(outerViewWidth: width, outerViewHeight: height)
    if adjustsFontSizeToFitWidth,
      initials.width(considering: textRect.height, and: font) > textRect.width {
      let newFontSize = calculateFontSize(text: initials, font: font, width: textRect.width, height: textRect.height)
      font = placeholderFont.withSize(newFontSize)
    }
    
    let textStyle = NSMutableParagraphStyle()
    textStyle.alignment = .center
    let textFontAttributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key.font: font, NSAttributedString.Key.foregroundColor: placeholderTextColor, NSAttributedString.Key.paragraphStyle: textStyle]
    
    let textTextHeight: CGFloat = initials.boundingRect(with: CGSize(width: textRect.width, height: CGFloat.infinity), options: .usesLineFragmentOrigin, attributes: textFontAttributes, context: nil).height
    
    let renderedImage = NSImage(size: NSSize(width: width, height: height))
    
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(renderedImage.size.width), pixelsHigh: Int(renderedImage.size.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return NSImage() }
    
    renderedImage.addRepresentation(rep)
    
    renderedImage.lockFocus()
    let drawBox = CGRect(textRect.minX, textRect.minY + (textRect.height - textTextHeight) / 2, textRect.width, textTextHeight)
    initials.draw(in: drawBox, withAttributes: textFontAttributes)
    renderedImage.unlockFocus()
    return renderedImage
  }
  
  /**
   Recursively find the biggest size to fit the text with a given width and height
   */
  private func calculateFontSize(text: String, font: NSFont, width: CGFloat, height: CGFloat) -> CGFloat {
    if text.width(considering: height, and: font) > width {
      let newFont = font.withSize(font.pointSize - 1)
      if newFont.pointSize > minimumFontSize {
        return font.pointSize
      } else {
        return calculateFontSize(text: text, font: newFont, width: width, height: height)
      }
    }
    return font.pointSize
  }
  
  /**
   Calculates the inner circle's width.
   Note: Assumes corner radius cannot be more than width/2 (this creates circle).
   */
  private func calculateTextRect(outerViewWidth: CGFloat, outerViewHeight: CGFloat) -> CGRect {
    guard outerViewWidth > 0 else {
      return CGRect.zero
    }
    let shortEdge = min(outerViewHeight, outerViewWidth)
    // Converts degree to radian degree and calculate the
    // Assumes, it is a perfect circle based on the shorter part of ellipsoid
    // calculate a rectangle
    let angle = CGFloat(45).degreesToRadians
    let w = shortEdge * sin(angle) * 2
    let h = shortEdge * cos(angle) * 2
    let startX = (outerViewWidth - w)/2
    let startY = (outerViewHeight - h)/2
    // In case the font exactly fits to the region, put 2 pixel both left and right
    return CGRect(startX+2, startY, w-4, h)
  }
  
  required public init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  // MARK: - Internal methods
  
  internal func prepareView() {
    self.postsFrameChangedNotifications = false
    self.postsBoundsChangedNotifications = false

    self.layer = CALayer()
    self.layer?.contentsGravity = CALayerContentsGravity.resizeAspectFill
    wantsLayer = true
    imageScaling = .scaleProportionallyUpOrDown
    layer?.backgroundColor = NSColor.gray.cgColor
    layer?.masksToBounds = true
    setCorner(radius: nil)
  }
  
  // MARK: - Open setters
  
  open func set(avatar: Avatar) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    if let image = avatar.image {
      self.image = image
      self.layer?.contents = image
    } else {
      initials = avatar.initials
    }
    CATransaction.commit()
  }
  
  open func setCorner(radius: CGFloat?) {
    guard let radius = radius else {
      //if corner radius not set default to Circle
      let cornerRadius = min(frame.width, frame.height)
      layer?.cornerRadius = cornerRadius/2
      return
    }
    self.radius = radius
    layer?.cornerRadius = radius
  }
  
  open override func resetCursorRects() {
    if let cursor = self.cursor {
      addCursorRect(self.bounds, cursor: cursor)
    } else {
      super.resetCursorRects()
    }
  }
  
  open override func mouseDown(with event: NSEvent) {
    if let target = self.target as? NSObject, let action = self.action {
      target.perform(action)
    }
  }
  
  open override func prepareForReuse() {
    super.prepareForReuse()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    layer?.contents = nil
    CATransaction.commit()
  }
}

fileprivate extension FloatingPoint {
  var degreesToRadians: Self { return self * .pi / 180 }
  var radiansToDegrees: Self { return self * 180 / .pi }
}
