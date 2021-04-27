//
//  Lock.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 27/04/2021.
//

import Foundation

public class Lock {
    private let queue = DispatchQueue(label: "fr.read-write.WiredLock", attributes: .concurrent)
    
    public init() {
        
    }
    
    public func concurrentlyRead<T>(_ block: (() throws -> T)) rethrows -> T {
        return try queue.sync {
            try block()
        }
    }
    
    public func exclusivelyWrite(_ block: @escaping (() -> Void)) {
        queue.async(flags: .barrier) {
            block()
        }
    }
}
