//
//  CompatibilityDiff.swift
//  WiredSwift
//
//  Captures the result of a `p7.compatibility_check.specification` exchange:
//  what the remote peer knows that we don't, and vice-versa. Used by
//  senders to gate features added in newer minor versions of the spec, and
//  for diagnostics.
//
//  See COMPATIBILITY.md for the policy.
//

import Foundation

/// The outcome of comparing the local `P7Spec` against a peer's `P7Spec`.
///
/// Computed once per session, after the optional `compatibility_check`
/// exchange in the handshake. A non-empty diff is **not** an error — minor
/// version drift is expected, and senders should consult this struct before
/// emitting newly-introduced messages or fields.
public struct CompatibilityDiff {
    /// Message IDs known to the local spec but absent from the remote spec.
    /// Sending one of these to the peer is likely to be ignored or trigger
    /// an `unrecognized_message` reply, so callers should fall back.
    public let messagesUnknownToRemote: Set<UInt32>

    /// Message IDs known to the remote spec but absent locally. We may
    /// still receive these on the wire — receiver-side tolerance keeps the
    /// session alive (see `P7Message.hasUnknownMessageID`).
    public let messagesUnknownToLocal: Set<UInt32>

    /// Field IDs known locally but not by the peer. Senders should omit
    /// these fields in messages destined for this peer.
    public let fieldsUnknownToRemote: Set<UInt32>

    /// Field IDs known by the peer but not locally. Will be skipped at
    /// decode time (with a corresponding entry in `unknownFieldIDs`).
    public let fieldsUnknownToLocal: Set<UInt32>

    /// `true` iff the two specs declare the same set of message and field
    /// IDs. Convenient shortcut for tests and diagnostics — does not imply
    /// semantic equivalence (types or ordering may still differ).
    public var isEmpty: Bool {
        messagesUnknownToRemote.isEmpty &&
        messagesUnknownToLocal.isEmpty &&
        fieldsUnknownToRemote.isEmpty &&
        fieldsUnknownToLocal.isEmpty
    }

    public static let identical = CompatibilityDiff(
        messagesUnknownToRemote: [],
        messagesUnknownToLocal: [],
        fieldsUnknownToRemote: [],
        fieldsUnknownToLocal: []
    )

    /// Compute the diff between two specs.
    public static func diff(local: P7Spec, remote: P7Spec) -> CompatibilityDiff {
        let localMsgIDs  = Set(local.messagesByID.keys.map { UInt32($0) })
        let remoteMsgIDs = Set(remote.messagesByID.keys.map { UInt32($0) })
        let localFldIDs  = Set(local.fieldsByID.keys)
        let remoteFldIDs = Set(remote.fieldsByID.keys)

        return CompatibilityDiff(
            messagesUnknownToRemote: localMsgIDs.subtracting(remoteMsgIDs),
            messagesUnknownToLocal: remoteMsgIDs.subtracting(localMsgIDs),
            fieldsUnknownToRemote: localFldIDs.subtracting(remoteFldIDs),
            fieldsUnknownToLocal: remoteFldIDs.subtracting(localFldIDs)
        )
    }
}
