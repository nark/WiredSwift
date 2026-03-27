//
//  File.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 19/04/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Foundation

/// A field definition parsed from a `<p7:field>` element in the P7 spec XML.
///
/// Every field has a wire type (`P7SpecType`) that determines how its value is
/// encoded in binary frames and a flag indicating whether it must be present
/// in messages that declare it.
public class P7SpecField: P7SpecItem {
    public var type: P7SpecType!
    public var required: Bool = false

    /// Creates a field definition from its XML attributes.
    ///
    /// The `type` property is resolved from the `"type"` attribute string via
    /// `P7SpecType.specType(forString:)`.
    ///
    /// - Parameters:
    ///   - name: The field's spec name (e.g. `"wired.user.login"`).
    ///   - spec: The owning `P7Spec` instance.
    ///   - attributes: The raw XML attributes of the `<p7:field>` element.
    public override init(name: String, spec: P7Spec, attributes: [String: Any]) {
        super.init(name: name, spec: spec, attributes: attributes)

        if let typeName = attributes["type"] as? String {
            self.type = P7SpecType.specType(forString: typeName)
        }
    }

    /// Returns `true` when the field's binary encoding includes a 4-byte length prefix.
    ///
    /// `.string`, `.data`, and `.list` fields carry an explicit length; all other
    /// fixed-size types (bool, int32, uuid, etc.) do not.
    ///
    /// - Returns: `true` for variable-length types that encode a length prefix on the wire.
    public func hasExplicitLength() -> Bool {
        return type == .string || type == .data || type == .list
    }
}
