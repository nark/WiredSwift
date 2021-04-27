//
//  SpeedCalculator.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 25/04/2021.
//

import Foundation


public class SpeedCalculator {
    private var index:Int       = 0
    private var length:Int      = 50
    
    private var bytes:[Int]     = []
    private var times:[Double]  = []
    
    
    public init() {
        
    }
    
    
    public func add(bytes:Int, time:Double) {
        if self.bytes.count == self.length {
            self.bytes.removeFirst()
            self.times.removeFirst()
        }
        
        self.bytes.append(bytes)
        self.times.append(time)
    }
    
    /// Calculate average
    public func speed() -> Double {
        return self.bytes.average / self.times.average
    }
}
