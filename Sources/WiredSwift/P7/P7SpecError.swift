//
//  File.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 19/04/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Foundation

/// An error definition parsed from a `<p7:enum>` element whose name begins with `"wired.error."`.
///
/// Error entries are collected from the spec XML into `P7Spec.errorsByID` and
/// `P7Spec.errorsByName`, allowing the receiver to map a numeric error code
/// carried in a `wired.error` field back to its human-readable name.
public class P7SpecError: P7SpecItem {

}
