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
import MapKit

open class LocationMessageItem: MessageCollectionViewItem {
  
  open override class func reuseIdentifier() -> NSUserInterfaceItemIdentifier {
    return NSUserInterfaceItemIdentifier("messagekit.cell.location")
  }
  
  // MARK: - Properties
  
  open var activityIndicator: NSProgressIndicator = {
    let indicator = NSProgressIndicator()
    indicator.style = .spinning
    return indicator
  }()
  
  //    public override init(frame: CGRect) {
  //        super.init(frame: frame)
  //    }
  
  public required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  public override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
    super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
  }
  
  private weak var snapShotter: MKMapSnapshotter?
  
  open override func setupSubviews() {
    super.setupSubviews()
    
    let imageView = NSImageView()
    imageView.layer = CALayer()
    imageView.layer?.contentsGravity = CALayerContentsGravity.resizeAspectFill
    imageView.wantsLayer = true
    
    self.imageView = imageView
    messageContainerView.addSubview(imageView)
    messageContainerView.addSubview(activityIndicator)
    setupConstraints()
  }
  
  open func setupConstraints() {
    imageView?.fillSuperview()
    activityIndicator.centerInSuperview()
  }
  
  open override func prepareForReuse() {
    super.prepareForReuse()
    snapShotter?.cancel()
  }
  
  open override func configure(with message: MessageType, at indexPath: IndexPath, and messagesCollectionView: MessagesCollectionView) {
    super.configure(with: message, at: indexPath, and: messagesCollectionView)
    guard let displayDelegate = messagesCollectionView.messagesDisplayDelegate else {
      fatalError(MessageKitError.nilMessagesDisplayDelegate)
    }
    let options = displayDelegate.snapshotOptionsForLocation(message: message, at: indexPath, in: messagesCollectionView)
    let annotationView = displayDelegate.annotationViewForLocation(message: message, at: indexPath, in: messagesCollectionView)
    let animationBlock = displayDelegate.animationBlockForLocation(message: message, at: indexPath, in: messagesCollectionView)
    
    guard case let .location(location) = message.data else { fatalError("") }
    
    activityIndicator.startAnimation(self)
    
    let snapshotOptions = MKMapSnapshotter.Options()
    snapshotOptions.mapType = options.mapType
    
    if let span = options.span {
      snapshotOptions.region = MKCoordinateRegion(center: location.coordinate, span: span)
    } else {
      let meters = options.spanRadiusMiles * 1609.34
      let region = MKCoordinateRegion(center: location.coordinate, latitudinalMeters: meters, longitudinalMeters: meters)
      snapshotOptions.region = region
    }
    
    snapshotOptions.showsBuildings = options.showsBuildings
    snapshotOptions.showsPointsOfInterest = options.showsPointsOfInterest
    
    let snapShotter = MKMapSnapshotter(options: snapshotOptions)
    self.snapShotter = snapShotter
    snapShotter.start { (snapshot, error) in
      defer {
        self.activityIndicator.stopAnimation(self)
        self.activityIndicator.isHidden = true
      }
      guard let snapshot = snapshot, error == nil else {
        //show an error image?
        return
      }
      
      guard let annotationView = annotationView else {
        self.imageView?.image = snapshot.image
        return
      }
      
      let composedImage = NSImage(size: snapshotOptions.size)
      let imageFrame = NSRect(origin: .zero, size: snapshotOptions.size)
      
      composedImage.lockFocus()
      
      snapshot.image.draw(at: .zero, from: imageFrame, operation: .overlay, fraction: 1)
      
      var point = snapshot.point(for: location.coordinate)
      //Move point to reflect annotation anchor
      point.x -= annotationView.bounds.size.width / 2
      point.y -= annotationView.bounds.size.height / 2
      point.x += annotationView.centerOffset.x
      point.y -= annotationView.centerOffset.y
      
      annotationView.image?.draw(at: point, from: imageFrame, operation: .sourceOver, fraction: 1)
      composedImage.unlockFocus()
      
      if let imageView = self.imageView {
        imageView.layer?.contents = composedImage
        animationBlock?(imageView)
      }
    }
  }
}
