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

open class MessageContainerView: NSImageView {

    // MARK: - Properties

    private var mask: CALayer?

    open var style: MessageStyle = .none {
        didSet {
            applyMessageStyle()
        }
    }

    open override var frame: CGRect {
        didSet {
            mask = style.generateMask(for: self.bounds)
            layer?.mask = mask
        }
    }

    // MARK: - Methods

    private func applyMessageStyle() {
        wantsLayer = true
        
        mask = nil
        
        switch style {
        case .bubble:
            layer?.cornerRadius = 16
            
        case .bubbleTail:
            mask = style.generateMask(for: self.bounds)
        case .bubbleOutline(let color):
            layer?.cornerRadius = 16
            layer?.borderColor = color.cgColor
            layer?.borderWidth = 1

        case .bubbleTailOutline(let color, let tail, let corner):
            let bubbleStyle: MessageStyle = .bubbleTailOutline(color, tail, corner)
            mask = bubbleStyle.generateMask(for: self.bounds)
        case .none:
            break
        case .custom(let configurationClosure):
            configurationClosure(self)
        }
        
        layer?.mask = mask
        
    }
}
