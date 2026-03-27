//
//  WiredError.swift
//  Wired
//
//  Created by Rafael Warnault on 17/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Foundation

/// An `NSObject`-based `Error` that wraps a Wired protocol error.
///
/// Errors can originate from the protocol spec (`SpecError`), from an explicit title/message pair,
/// or directly from a `wired.error` `P7Message` received from the server.
public class WiredError: NSObject, Error {
    public var specError: SpecError?

    private var errorTitle: String
    private var errorMessage: String

    /// Creates an error from a `SpecError` defined in the protocol spec.
    ///
    /// - Parameter specError: The spec-level error whose `name` and `description` populate this instance.
    public init(withSPecError specError: SpecError) {
        self.specError = specError

        if let se = self.specError {
            errorTitle = se.name
            errorMessage = se.description
        } else {
            errorTitle = "Unknown error"
            errorMessage = "Unknown error message"
        }
    }

    /// Creates an error with an explicit title and message.
    ///
    /// - Parameters:
    ///   - title: A short human-readable error title.
    ///   - message: A longer description of the error.
    public init(withTitle title: String, message: String) {
        self.errorTitle = title
        self.errorMessage = message
    }

    /// Creates an error from a `wired.error` server message.
    ///
    /// Reads the `wired.error.string` field from the message to populate the error description.
    ///
    /// - Parameter message: A `P7Message` with name `wired.error` received from the server.
    public init(message: P7Message) {
        self.errorTitle = "Server Error"
        self.errorMessage = message.string(forField: "wired.error.string") ?? "No error message"
    }

    public override var description: String {
        return "\(self.errorTitle): \(self.errorMessage)"
    }

    /// A short human-readable title for this error.
    public var title: String {
        self.errorTitle
    }

    /// A detailed description of this error.
    public var message: String {
        self.errorMessage
    }
}
