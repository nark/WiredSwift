//
//  Lock.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 27/04/2021.
//

import Foundation

/// A reader-writer lock that allows concurrent reads and serialised writes.
///
/// Internally backed by a `DispatchQueue` with the `.concurrent` attribute.
/// Multiple readers may execute simultaneously; writers execute exclusively using a barrier.
public class Lock {
    private let queue = DispatchQueue(label: "fr.read-write.WiredLock", attributes: .concurrent)

    /// Creates a new reader-writer lock.
    public init() {

    }

    /// Executes `block` under a shared (read) lock and returns its result.
    ///
    /// Multiple concurrent readers are allowed. The call blocks until any active writer finishes.
    ///
    /// - Parameter block: A throwing closure whose return value is forwarded to the caller.
    /// - Returns: The value returned by `block`.
    /// - Throws: Any error thrown by `block`.
    public func concurrentlyRead<T>(_ block: (() throws -> T)) rethrows -> T {
        return try queue.sync {
            try block()
        }
    }

    /// Executes `block` under an exclusive (write) barrier and returns its result.
    ///
    /// No other reader or writer may run concurrently. The call blocks until all active readers finish.
    ///
    /// - Parameter block: A throwing closure whose return value is forwarded to the caller.
    /// - Returns: The value returned by `block`.
    /// - Throws: Any error thrown by `block`.
    @discardableResult
    public func exclusivelyWrite<T>(_ block: (() throws -> T)) rethrows -> T {
        try queue.sync(flags: .barrier) {
            try block()
        }
    }
}
