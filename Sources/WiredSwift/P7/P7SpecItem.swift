//
//  File.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 19/04/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Foundation

/// Abstract base class for all items parsed from a P7 spec XML file.
///
/// Concrete subclasses include `P7SpecField`, `P7SpecMessage`, and `P7SpecError`.
/// Each item carries the raw XML attributes from its element so subclasses can
/// access protocol-specific properties without re-parsing.
public class P7SpecItem: NSObject {
    public var spec: P7Spec!
    public var name: String!
    public var id: String!
    public var version: String?
    public var attributes: [String: Any] = [:]

    /// Creates a new spec item with the given name, owning spec, and XML attributes.
    ///
    /// - Parameters:
    ///   - name: The element's `name` attribute from the XML spec.
    ///   - spec: The `P7Spec` instance that owns this item.
    ///   - attributes: The full dictionary of XML attributes for the element.
    public init(name: String, spec: P7Spec, attributes: [String: Any]) {
        self.spec       = spec
        self.name       = name
        self.id         = attributes["id"] as? String
        self.version    = attributes["version"] as? String
        self.attributes = attributes
    }

    /// Returns a human-readable `[id] name` string for the item.
    public override var description: String {
        // SECURITY (FINDING_P_019): nil-coalescing instead of force unwrap
        return "[\(self.id ?? "?")] \(self.name ?? "unknown")"
    }
}
