//
//  OptionSet+Collection.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 20/04/2021.
//

import Foundation

/// This is a useful index that can store a comparable element or the end of
/// a collection. Similar to https://github.com/apple/swift/pull/15193
public enum IndexWithEnd<T : Comparable> : Comparable {
  case element(T)
  case end
  
    public static func < (lhs: IndexWithEnd, rhs: IndexWithEnd) -> Bool {
    switch (lhs, rhs) {
    case (.element(let l), .element(let r)):
      return l < r
    case (.element, .end):
      return true
    case (.end, .element), (.end, .end):
      return false
    }
  }
}

/// This extension provides all the Collection requirements to an OptionSet
/// that specifies that its Index is the type above.
public  extension Collection
  where Self : OptionSet, Self.RawValue : FixedWidthInteger,
  Index == IndexWithEnd<Self.RawValue>
{
  func _rawBit(after value: RawValue) -> RawValue? {
    let shift = value.trailingZeroBitCount + 1
    let shiftedRawValue = rawValue >> shift
    if shiftedRawValue == 0 {
      return nil
    } else {
      return (1 as RawValue) << (shiftedRawValue.trailingZeroBitCount + shift)
    }
  }
  
  var startIndex: Index {
    return rawValue == 0
      ? .end
      : .element(1 << rawValue.trailingZeroBitCount)
  }
  
  var endIndex: Index {
    return .end
  }
  
  var isEmpty: Bool {
    return rawValue == 0
  }
  
  var count: Int {
    return rawValue.nonzeroBitCount
  }
  
  subscript(i: Index) -> Self {
    switch i {
    case .element(let e):
      return Self(rawValue: e)
    case .end:
      fatalError("Can't subscript with endIndex")
    }
  }
  
  func index(after i: Index) -> Index {
    switch i {
    case .element(let e):
      return _rawBit(after: e).map({ .element($0) }) ?? .end
    case .end:
      fatalError("Can't advance past endIndex")
    }
  }
}
