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

public enum MessageStyle {

    // MARK: - TailCorner

    public enum TailCorner {

        case topLeft
        case bottomLeft
        case topRight
        case bottomRight

//        var imageOrientation: UIImageOrientation {
//            switch self {
//            case .bottomRight: return .up
//            case .bottomLeft: return .upMirrored
//            case .topLeft: return .down
//            case .topRight: return .downMirrored
//            }
//        }
    }

    // MARK: - TailStyle

    public enum TailStyle {

        case curved
        case pointedEdge

        var imageNameSuffix: String {
            switch self {
            case .curved:
                return "_tail_v2"
            case .pointedEdge:
                return "_tail_v1"
            }
        }
    }

    // MARK: - MessageStyle

    case none
    case bubble
    case bubbleOutline(NSColor)
    case bubbleTail(TailCorner, TailStyle)
    case bubbleTailOutline(NSColor, TailCorner, TailStyle)
    case custom((MessageContainerView) -> Void)

    // MARK: - Public

    public func generateMask(for rect: NSRect) -> CALayer? {
        
        switch self {
        case .none, .custom:
            return nil
        case .bubble, .bubbleOutline:
            return nil
        case .bubbleTail(let corner, _), .bubbleTailOutline(_, let corner, _):
            switch corner {
            case .bottomRight:
                return generateMaskTailRight(for: rect)
            default:
                return generateMaskTailLeft(for: rect)
            }
        }
    }
    
    private func generateMaskTailLeft(for rect: NSRect) -> CALayer? {
        let shape = CAShapeLayer()
        
        let tailWidth: CGFloat = 16
        let tailMargin = tailWidth / 2
        let tailHeight: CGFloat = 16
        let tailStart: CGFloat = tailWidth * 2
        let peakHeight: CGFloat = 4
        let cornerRadius: CGFloat = min(16, (rect.maxX / 2))

        let path = CGMutablePath()
        
        // End of tail
        path.move(to: rect.origin)
        
        // Upper tail curve
        path.addQuadCurve(to: CGPoint(x: rect.minX + tailMargin,
                                      y: rect.minY + tailHeight),
                          control: CGPoint(x: rect.minX + tailMargin,
                                           y: rect.minY))
        
        // Left edge
        path.addLine(to: CGPoint(x: rect.minY + tailMargin,
                                 y: rect.maxY - cornerRadius))
        
        // Upper left corner
        path.addArc(tangent1End: CGPoint(x: rect.minX + tailMargin,
                                         y: rect.maxY),
                    tangent2End: CGPoint(x: rect.minX + tailMargin + cornerRadius,
                                         y: rect.maxY),
                    radius: cornerRadius)
        
        // Upper edge
        path.addLine(to: CGPoint(x: rect.maxX - cornerRadius,
                                 y: rect.maxY))
        
        // Upper right corner
        path.addArc(tangent1End: CGPoint(x: rect.maxX,
                                         y: rect.maxY),
                    tangent2End: CGPoint(x: rect.maxX,
                                         y: rect.maxY - cornerRadius),
                    radius: cornerRadius)
        
        // Right edge
        path.addLine(to: CGPoint(x: rect.maxX , y: rect.minY + cornerRadius))
        
        
        // Bottom right corner
        path.addArc(tangent1End: CGPoint(x: rect.maxX,
                                         y: rect.minY),
                    tangent2End: CGPoint(x: rect.maxX - cornerRadius,
                                         y: rect.minY),
                    radius: cornerRadius)
        
        // Bottom edge
        path.addLine(to: CGPoint(x: rect.minX + tailStart, y: rect.minY))
        
        // Curve up
        path.addQuadCurve(to: CGPoint(x: rect.minX + tailWidth,
                                      y: rect.minY + peakHeight),
                          control: CGPoint(x: rect.minX + tailWidth + peakHeight,
                                           y: rect.minY))
        
        // Curve back down to corner
        path.addQuadCurve(to: CGPoint(x: rect.minX,
                                      y: rect.minY),
                          control: CGPoint(x: rect.minX + tailWidth - peakHeight,
                                           y: rect.minY))
        path.closeSubpath()
        
        shape.path = path
        
        return shape
    }
    
    private func generateMaskTailRight(for rect: NSRect) -> CALayer? {
        let shape = CAShapeLayer()
        
        let tailWidth: CGFloat = 16
        let tailMargin = tailWidth / 2
        let tailStart: CGFloat = tailWidth * 2
        let peakHeight: CGFloat = 4
        let cornerRadius: CGFloat = min(16, (rect.maxX / 2))
        
        let path = CGMutablePath()
        
        // Start before upper left corner
        path.move(to: CGPoint(x: rect.minX,
                              y: rect.maxY - cornerRadius))
        
        // Upper left corner
        path.addArc(tangent1End: CGPoint(x: rect.minX,
                                         y: rect.maxY),
                    tangent2End: CGPoint(x: rect.minX + cornerRadius,
                                         y: rect.maxY),
                    radius: cornerRadius)
        
        // Upper edge
        path.addLine(to: CGPoint(x: rect.maxX - cornerRadius,
                                 y: rect.maxY))
        
        // Upper right corner
        path.addArc(tangent1End: CGPoint(x: rect.maxX - tailMargin,
                                         y: rect.maxY),
                    tangent2End: CGPoint(x: rect.maxX - tailMargin,
                                         y: rect.maxY - cornerRadius),
                    radius: cornerRadius)
        
        // Right edge
        path.addLine(to: CGPoint(x: rect.maxX - tailMargin , y: rect.minY + cornerRadius))
        
        
        // Curve to corner
        path.addQuadCurve(to: CGPoint(x: rect.maxX,
                                      y: rect.minY),
                          control: CGPoint(x: rect.maxX - tailMargin,
                                           y: rect.minY))
        
        // Curve back up from corner
        path.addQuadCurve(to: CGPoint(x: rect.maxX - tailWidth,
                                      y: rect.minY + peakHeight),
                          control: CGPoint(x: rect.maxX - tailWidth + peakHeight,
                                           y: rect.minY))

        // Curve back down to bottom edge
        path.addQuadCurve(to: CGPoint(x: rect.maxX - tailStart,
                                      y: rect.minY),
                          control: CGPoint(x: rect.maxX - tailWidth - peakHeight,
                                           y: rect.minY))

        // Bottom edge
        path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: rect.minY))

        // Bottom right corner
        path.addArc(tangent1End: CGPoint(x: rect.minX,
                                         y: rect.minY),
                    tangent2End: CGPoint(x: rect.minX,
                                         y: rect.minY + cornerRadius),
                    radius: cornerRadius)
        
        
        path.closeSubpath()
        
        shape.path = path
        
        return shape
    }
    


}
