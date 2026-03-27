//
//  File.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 19/04/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Foundation

/// A message definition parsed from a `<p7:message>` element in the P7 spec XML.
///
/// Each instance holds the ordered list of `P7SpecField` parameters declared
/// for the message, allowing callers to validate or enumerate the fields a
/// particular message is expected to carry.
public class P7SpecMessage: P7SpecItem {
    /// The ordered list of field definitions declared as parameters of this message.
    public var parameters: [P7SpecField] = []

    /// Creates a message definition from its XML attributes.
    ///
    /// - Parameters:
    ///   - name: The message's spec name (e.g. `"wired.send_login"`).
    ///   - spec: The owning `P7Spec` instance.
    ///   - attributes: The raw XML attributes of the `<p7:message>` element.
    public override init(name: String, spec: P7Spec, attributes: [String: Any]) {
        super.init(name: name, spec: spec, attributes: attributes)
    }
}
