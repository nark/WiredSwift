//
//  Transfer.swift
//  wired3
//
//  Created by Rafael Warnault on 24/04/2021.
//

import Foundation
import WiredSwift

/// Represents an in-progress or queued file transfer (upload or download).
///
/// A `Transfer` is created when a client issues a file transfer request and
/// is attached to the owning `Client` for the duration of the transfer.
public class Transfer: Equatable {
    struct StatusSnapshot {
        let type: TransferType
        let path: String
        let dataSize: UInt64
        let rsrcSize: UInt64
        let transferred: UInt64
        let speed: UInt32
        let queuePosition: Int
    }

    /// Whether this transfer sends a file to the client or receives one from it.
    public enum TransferType: UInt32 {
        /// The server is sending a file to the client.
        case download = 0
        /// The client is sending a file to the server.
        case upload
    }

    /// Current execution state of the transfer.
    public enum TransferState: UInt32 {
        /// Transfer is waiting in the server queue.
        case queued = 0
        /// Transfer is actively transferring data.
        case running
    }

    var client: Client
    var path: String

    var key: String!
    var realDataPath: String!
    var realRsrcPath: String!

    var dataFd: FileHandle!
    var rsrcFd: FileHandle!

    var state: TransferState
    var type: TransferType
    var executable: Bool = false

    let queueLock = DispatchSemaphore(value: 1)
    var queuePosition: Int = 0
//    var queue_lock
//    var queue
//    var queue_time

    var dataOffset: UInt64!
    var rsrcOffset: UInt64!
    var dataSize: UInt64!
    var rsrcSize: UInt64!
    var remainingDataSize: UInt64!
    var remainingRsrcSize: UInt64!
    var transferred: UInt64!
    var actualTransferred: UInt64!
    var speed: UInt32 = 0
    private let metricsLock = NSLock()
    private let speedCalculator = SpeedCalculator()
    private var speedSampleBytes: Int = 0
    private var speedSampleStart: TimeInterval = Date.timeIntervalSinceReferenceDate

//    var speed
//    var finderinfo

    /// Creates a new `Transfer` in the queued state.
    ///
    /// - Parameters:
    ///   - path: Virtual server-side path of the file being transferred.
    ///   - client: The `Client` that initiated the transfer.
    ///   - message: The originating P7 protocol message carrying transfer parameters.
    ///   - type: Whether this is a `.download` or `.upload`.
    public init(path: String, client: Client, message: P7Message, type: TransferType) {
        self.path   = path
        self.client = client
        self.type   = type
        self.state  = .queued
    }

    /// Two `Transfer` instances are equal when they are the same object reference.
    ///
    /// - Returns: `true` if `lhs` and `rhs` are identical objects.
    public static func == (lhs: Transfer, rhs: Transfer) -> Bool {
        lhs === rhs
    }

    func beginSpeedMeasurement(at now: TimeInterval = Date.timeIntervalSinceReferenceDate) {
        metricsLock.lock()
        speed = 0
        speedSampleBytes = 0
        speedSampleStart = now
        metricsLock.unlock()
    }

    func noteTransferredBytes(_ bytes: UInt64, at now: TimeInterval = Date.timeIntervalSinceReferenceDate) {
        metricsLock.lock()
        transferred += bytes
        actualTransferred += bytes
        speedSampleBytes += Int(bytes)

        let elapsed = now - speedSampleStart
        if elapsed >= 0.25 {
            speedCalculator.add(bytes: speedSampleBytes, time: max(0.001, elapsed))
            speed = UInt32(clamping: Int(speedCalculator.speed().rounded()))
            speedSampleBytes = 0
            speedSampleStart = now
        }
        metricsLock.unlock()
    }

    func finishSpeedMeasurement(at now: TimeInterval = Date.timeIntervalSinceReferenceDate) {
        metricsLock.lock()
        let elapsed = now - speedSampleStart
        if speedSampleBytes > 0 && elapsed > 0 {
            speedCalculator.add(bytes: speedSampleBytes, time: max(0.001, elapsed))
            speed = UInt32(clamping: Int(speedCalculator.speed().rounded()))
            speedSampleBytes = 0
        }
        metricsLock.unlock()
    }

    func statusSnapshot() -> StatusSnapshot {
        metricsLock.lock()
        let snapshot = StatusSnapshot(
            type: type,
            path: path,
            dataSize: dataSize ?? 0,
            rsrcSize: rsrcSize ?? 0,
            transferred: transferred ?? 0,
            speed: speed,
            queuePosition: queuePosition
        )
        metricsLock.unlock()
        return snapshot
    }
}
