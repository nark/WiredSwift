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

/**
 A UITextView that has a UILabel embedded for placeholder text
 
 ## Important Notes ##
 1. Changing the font, textAlignment or textContainerInset automatically performs the same modifications to the placeholderLabel
 2. Intended to be used in an `MessageInputBar`
 3. Default placeholder text is "New Message"
 4. Will pass a pasted image it's `MessageInputBar`'s `InputManager`s
 */
open class InputTextView: NSTextView {
    
    // MARK: - Properties
    
//    open override var stringValue: String {
//        didSet {
//            postTextViewDidChangeNotification()
//        }
//    }
//
//    open override var attributedStringValue: NSAttributedString {
//        didSet {
//            postTextViewDidChangeNotification()
//        }
//    }
    
    /// The images that are currently stored as NSTextAttachment's
    open var images: [NSImage] {
        return parseForAttachedImages()
    }
    
    open var components: [Any] {
        return parseForComponents()
    }
    
    open var isImagePasteEnabled: Bool = true
    
//    open override var scrollIndicatorInsets: NSEdgeInsets {
//        didSet {
//            // When .zero a rendering issue can occur
//            if scrollIndicatorInsets == .zero {
//                scrollIndicatorInsets = NSEdgeInsets(top: .leastNonzeroMagnitude,
//                                                     left: .leastNonzeroMagnitude,
//                                                     bottom: .leastNonzeroMagnitude,
//                                                     right: .leastNonzeroMagnitude)
//            }
//        }
//    }
    
    /// A weak reference to the MessageInputBar that the InputTextView is contained within
    open weak var messageInputBar: MessageInputBar?
    
    // MARK: - Initializers

    public override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        setup()
    }
    
    public convenience init() {
        self.init(frame: NSRect.zero)
    }
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }
    
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }
    
    
    // MARK: - Setup
    
    /// Sets up the default properties
    open func setup() {
        
        font = NSFont.preferredFont(forTextStyle: .body)
        wantsLayer = true
        layer?.cornerRadius = 5.0
        layer?.borderWidth = 1.25
        layer?.borderColor = NSColor.lightGray.cgColor
        
        setContentCompressionResistancePriority(NSLayoutConstraint.Priority.defaultHigh, for: NSLayoutConstraint.Orientation.horizontal)
        setContentCompressionResistancePriority(NSLayoutConstraint.Priority.defaultHigh, for: NSLayoutConstraint.Orientation.vertical)
    }

    
    // MARK: - Notification
    
//    private func postTextViewDidChangeNotification() {
//        NotificationCenter.default.post(name: .UITextViewTextDidChange, object: self)
//    }
    
    // MARK: - Image Paste Support
    
//    open override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
//
//        if action == NSSelectorFromString("paste:") && UIPasteboard.general.image != nil {
//            return isImagePasteEnabled
//        }
//        return super.canPerformAction(action, withSender: sender)
//    }
//
//    open override func paste(_ sender: Any?) {
//
//        guard let image = UIPasteboard.general.image else {
//            return super.paste(sender)
//        }
//        pasteImageInTextContainer(with: image)
//    }
    
    /// Addes a new UIImage to the NSTextContainer as an NSTextAttachment
    ///
    /// - Parameter image: The image to add
//    private func pasteImageInTextContainer(with image: UIImage) {
//
//        // Add the new image as an NSTextAttachment
//        let attributedImageString = NSAttributedString(attachment: textAttachment(using: image))
//
//        let isEmpty = attributedText.length == 0
//
//        // Add a new line character before the image, this is what iMessage does
//        let newAttributedStingComponent = isEmpty ? NSMutableAttributedString(string: "") : NSMutableAttributedString(string: "\n")
//        newAttributedStingComponent.append(attributedImageString)
//
//        // Add a new line character after the image, this is what iMessage does
//        newAttributedStingComponent.append(NSAttributedString(string: "\n"))
//
//        // The attributes that should be applied to the new NSAttributedString to match the current attributes
//        let attributes: [NSAttributedStringKey: Any] = [
//            NSAttributedStringKey.font: font ?? UIFont.preferredFont(forTextStyle: .body),
//            NSAttributedStringKey.foregroundColor: textColor ?? .black
//            ]
//        newAttributedStingComponent.addAttributes(attributes, range: NSRange(location: 0, length: newAttributedStingComponent.length))
//
//        textStorage.beginEditing()
//        // Paste over selected text
//        textStorage.replaceCharacters(in: selectedRange, with: newAttributedStingComponent)
//        textStorage.endEditing()
//
//        // Advance the range to the selected range plus the number of characters added
//        let location = selectedRange.location + (isEmpty ? 2 : 3)
//        selectedRange = NSRange(location: location, length: 0)
//
//        // Broadcast a notification to recievers such as the MessageInputBar which will handle resizing
//        NotificationCenter.default.post(name: .UITextViewTextDidChange, object: self)
//    }
    
    /// Returns an NSTextAttachment the provided image that will fit inside the NSTextContainer
    ///
    /// - Parameter image: The image to create an attachment with
    /// - Returns: The formatted NSTextAttachment
//    private func textAttachment(using image: NSImage) -> NSTextAttachment {
//
//        guard let cgImage = image.cgImage else { return NSTextAttachment() }
//        let scale = image.size.width / (frame.width - 2 * (textContainerInset.left + textContainerInset.right))
//        let textAttachment = NSTextAttachment()
//        textAttachment.image = NSImage(cgImage: cgImage, scale: scale, orientation: .up)
//        return textAttachment
//    }
    
    /// Returns all images that exist as NSTextAttachment's
    ///
    /// - Returns: An array of type UIImage
    private func parseForAttachedImages() -> [NSImage] {

        var images = [NSImage]()
        let attributedText = attributedString()
        let range = NSRange(location: 0, length: attributedText.length)
        attributedText.enumerateAttribute(.attachment, in: range, options: [], using: { value, range, _ -> Void in

            if let attachment = value as? NSTextAttachment {
                if let image = attachment.image {
                    images.append(image)
                } else if let image = attachment.image(forBounds: attachment.bounds,
                                                       textContainer: nil,
                                                       characterIndex: range.location) {
                    images.append(image)
                }
            }
        })
        return images
    }
    
    /// Returns an array of components (either a String or UIImage) that makes up the textContainer in
    /// the order that they were typed
    ///
    /// - Returns: An array of objects guaranteed to be of UIImage or String
    private func parseForComponents() -> [Any] {
        
        var components = [Any]()
        let attributedText = attributedString()
        let range = NSRange(location: 0, length: attributedText.length)
        attributedText.enumerateAttributes(in: range, options: []) { (object, range, _) in
            
            if object.keys.contains(.attachment) {
                if let attachment = object[.attachment] as? NSTextAttachment {
                    if let image = attachment.image {
                        components.append(image)
                    } else if let image = attachment.image(forBounds: attachment.bounds,
                                                           textContainer: nil,
                                                           characterIndex: range.location) {
                        components.append(image)
                    }
                }
            } else {
                let stringValue = attributedText.attributedSubstring(from: range).string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !stringValue.isEmpty {
                    components.append(stringValue)
                }
            }
        }
        return components
    }
    
//    /// Redraws the NSTextAttachments in the NSTextContainer to fit the current bounds
//    @objc
//    private func redrawTextAttachments() {
//
//        guard images.count > 0 else { return }
//        let range = NSRange(location: 0, length: attributedStringValue.length)
//        attributedStringValue.enumerateAttribute(.attachment, in: range, options: [], using: { value, _, _ -> Void in
//            if let attachment = value as? NSTextAttachment, let image = attachment.image {
//
//                // Calculates a new width/height ratio to fit the image in the current frame
//                let newWidth = frame.width - 2 * (textContainerInset.left + textContainerInset.right)
//                let ratio = image.size.height / image.size.width
//                attachment.bounds.size = CGSize(width: newWidth, height: ratio * newWidth)
//            }
//        })
//        layoutManager.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
//    }
    
}
