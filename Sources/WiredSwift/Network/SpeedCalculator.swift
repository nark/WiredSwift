//
//  SpeedCalculator.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 25/04/2021.
//

import Foundation

/// A rolling-window bytes-per-second calculator intended for file transfer progress UI.
///
/// Feed each transfer chunk into `add(bytes:time:)` and read the current average throughput
/// from `speed()`. The window is capped at 50 samples; older samples are discarded automatically.
public class SpeedCalculator {
    private var index: Int       = 0
    private var length: Int      = 50

    private var bytes: [Int]     = []
    private var times: [Double]  = []

    /// Creates a new calculator with an empty sample window.
    public init() {

    }

    /// Adds a transfer sample to the rolling window.
    ///
    /// When the window is full (50 entries) the oldest sample is discarded before inserting the new one.
    ///
    /// - Parameters:
    ///   - bytes: Number of bytes transferred in the sample interval.
    ///   - time: Duration of the sample interval in seconds.
    public func add(bytes: Int, time: Double) {
        if self.bytes.count == self.length {
            self.bytes.removeFirst()
            self.times.removeFirst()
        }

        self.bytes.append(bytes)
        self.times.append(time)
    }

    /// Returns the average transfer speed across all samples in the rolling window, in bytes per second.
    public func speed() -> Double {
        return self.bytes.average / self.times.average
    }
}
