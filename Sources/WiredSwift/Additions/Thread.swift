//
//  Thread.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 24/04/2021.
//

import Foundation
import Dispatch

extension Thread {

    var threadName: String {
        if let currentOperationQueue = OperationQueue.current?.name {
            return "OperationQueue: \(currentOperationQueue)"
        } else if let underlyingDispatchQueue = OperationQueue.current?.underlyingQueue?.label {
            return "DispatchQueue: \(underlyingDispatchQueue)"
        }
        #if os(iOS) || os(macOS)
            let name = __dispatch_queue_get_label(nil)
            return String(cString: name, encoding: .utf8) ?? Thread.current.description
        #else
            return "[Unknow thread]"
        #endif
    }
}
