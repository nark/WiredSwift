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

import MapKit
import AppKit

/// An object grouping the settings used by the `MKMapSnapshotter` through the `LocationMessageDisplayDelegate`.
public struct LocationMessageSnapshotOptions {
  
  /// Initialize LocationMessageSnapshotOptions with given parameters
  ///
  /// - Parameters:
  ///   - showsBuildings: A Boolean value indicating whether the snapshot image should display buildings.
  ///   - showsPointsOfInterest: A Boolean value indicating whether the snapshot image should display points of interest.
  ///   - span: The span of the snapshot.
  ///   - scale: The scale of the snapshot.
  public init(mapType: MKMapType = MKMapType.hybrid, showsBuildings: Bool = true, showsPointsOfInterest: Bool = true) {
    self.mapType = mapType
    self.showsBuildings = showsBuildings
    self.showsPointsOfInterest = showsPointsOfInterest
  }
  
  public var mapType: MKMapType
  
  /// A Boolean value indicating whether the snapshot image should display buildings.
  ///
  /// The default value of this property is `true`.
  public var showsBuildings: Bool
  
  /// A Boolean value indicating whether the snapshot image should display points of interest.
  ///
  /// The default value of this property is `true`.
  public var showsPointsOfInterest: Bool
  
  /// The span of the snapshot.
  ///
  /// The default value of this property uses a width of `0` and height of `0`.
  public var span: MKCoordinateSpan? = nil
  
  public var spanRadiusMiles: Double = 1
  
  /// The scale of the snapshot.
  ///
  /// The default value of this property uses the `NSScreen.main!.backingScaleFactor`.
  public var scale: CGFloat = NSScreen.main!.backingScaleFactor
  
}
