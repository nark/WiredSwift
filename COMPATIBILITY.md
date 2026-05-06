# Wired Protocol Compatibility Policy

This document defines how the Wired protocol evolves across versions, and the
contract that client and server implementations agree to follow so that peers
running different minor versions can interoperate gracefully.

It applies to both `WiredSwift` (this repository) and downstream clients such
as `Wired-macOS`, which embed the same protocol parser.

## Versioning

The Wired protocol version (declared in `Sources/WiredSwift/Resources/wired.xml`
and exchanged in the handshake under `p7.handshake.protocol.version`) follows
**semantic versioning**:

| Component | Meaning |
|-----------|---------|
| **Major** (`X.y.z`) | Wire-format break — field IDs reused, types changed, or framing redefined. Peers with different majors **refuse** to connect. |
| **Minor** (`x.Y.z`) | Backward- and forward-compatible additions: new optional fields, new optional messages, new enum values. Peers with different minors **must** interoperate. |
| **Patch** (`x.y.Z`) | Documentation, clarifications, or implementation fixes that do not change the wire. |

The P7 framing version (`p7.handshake.version`) follows the same rules — peers
with the same P7 major proceed; different majors abort the handshake.

## Negotiation

After the regular handshake exchanges versions, each peer stores the negotiated
versions on the `P7Socket`:

- `negotiatedProtocolVersion` — `min(local, remote)` of the Wired version.
- `negotiatedBuiltinProtocolVersion` — `min(local, remote)` of P7.

When the two Wired versions differ (any minor difference), the existing
`p7.compatibility_check.specification` exchange runs in both directions: each
peer ships its `wired.xml`, parses what it receives, and computes a
`CompatibilityDiff` describing which messages and fields the peer does **not**
know. The exchange is **never** rejected — the result is informational and
drives the runtime behaviour described below.

`P7Socket` exposes:

- `remoteSpec: P7Spec?` — the peer's parsed spec (when available).
- `compatibilityDiff: CompatibilityDiff` — symmetric set difference of message
  and field IDs.
- `peerKnows(messageNamed:)` / `peerKnows(fieldNamed:)` — convenience helpers.

## Wire-Format Constraints for New Fields

The P7 binary frame is TLV-ish: only `string`, `data`, and `list` types carry
an explicit 4-byte length prefix. Fixed-size types (`bool`, `enum`, `uint32`,
`uint64`, `int32`, `int64`, `double`, `date`, `uuid`, `oobdata`) derive their
size from the spec.

This has a forward-compat consequence: a peer that does not know a field ID
**cannot reliably skip a fixed-size field** — its size is unknown without the
spec. The parser therefore stops decoding the rest of the message body when it
hits an unknown field, and records the offending ID in
`P7Message.unknownFieldIDs` for diagnostics.

**Rule for protocol authors:** when adding a new optional field to the
protocol, prefer a **length-prefixed type** (`string`, `data`, `list`) so that
older peers — which do not know the new field — can fall through gracefully
without aborting the rest of the message decode. If a fixed-size type is
genuinely required (e.g., `uint32` or `bool`), the new field must be paired
with the diff machinery: senders must consult
`P7Socket.peerKnows(fieldNamed:)` before adding it to a message bound for the
peer, or the field will be filtered out automatically by `P7Socket.write(_:)`
based on `compatibilityDiff.fieldsUnknownToRemote`.

## Versioning Spec Items

Every `<p7:field>`, `<p7:message>`, and `<p7:enum>` introduced after the
initial 3.0 baseline **must** carry a `version="X.Y"` attribute matching the
Wired protocol version in which it was added. This is what makes the
`CompatibilityDiff` meaningful and lets us tell at a glance which spec items
are newer than a given peer's view of the world.

Existing items are versioned historically (`2.0`, `2.5`, `3.0`, etc.). Do not
remove or backdate the `version` attribute on existing items — that breaks the
historical record.

## Adding a Field — Checklist

1. Choose the smallest unused **field ID** in the relevant range.
2. Prefer a length-prefixed type unless a fixed size is required.
3. Add `version="X.Y"` matching the next Wired minor version on the entry.
4. If the field is fixed-size:
   - On the sender side, rely on the automatic filter in `P7Socket.write(_:)`
     (driven by `compatibilityDiff.fieldsUnknownToRemote`); do not add bespoke
     `if peerKnows(...)` guards unless the *absence* of the field changes the
     semantic meaning of the message and you need to take a different code
     path.
5. If the field is required (not optional), the change is **major** —
   bump the protocol major version and document the break.
6. Bump `version="X.Y"` on the `<p7:protocol>` root.

## Adding a Message — Checklist

1. Choose the smallest unused **message ID** in the relevant range.
2. Add `version="X.Y"` matching the next Wired minor version.
3. Senders should rely on the automatic message filter in `P7Socket.write(_:)`
   for messages whose absence is benign (notifications, broadcasts). For
   messages that expect a response, prefer an explicit
   `if socket.peerKnows(messageNamed: "...")` guard, falling back to a
   compatible behaviour when the peer cannot handle the message.
4. Receivers automatically tolerate unknown message IDs: the frame is logged
   and any recognised fields (notably `wired.transaction`) are still extracted
   so the upper layer can decide whether to reply with
   `wired.error.unrecognized_message`.

## Removing or Renaming an Item

Removing a field or message, or repurposing an ID for a different type, is a
**major** version break. Rename the spec entry instead and keep the old one
around as deprecated until the next major bump. Field/message IDs are part of
the wire and must be treated as permanent within a major.

## Receiver Tolerance

Both `P7Message` and `P7Socket` tolerate forward-compatible drift:

- **Unknown message IDs** are decoded best-effort (known fields extracted) and
  flagged via `P7Message.hasUnknownMessageID`.
- **Unknown field IDs** abort decoding of the rest of the message body and
  are recorded in `P7Message.unknownFieldIDs`. The fields decoded so far are
  preserved.
- The `compatibility_check` exchange never throws — incompatibilities are
  logged at WARNING level.

This combination of receiver tolerance, optional capability diff, and the
length-prefix rule allows a v3.1 client to talk to a v3.0 server (and vice
versa) without rebuilding either side.
