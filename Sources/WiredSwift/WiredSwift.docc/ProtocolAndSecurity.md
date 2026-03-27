# Protocol And Security

## Protocol Foundation

Wired 3 communication is encoded as P7 messages carried over encrypted sessions.
Core protocol structures are represented by ``P7Message``, ``P7Spec``, and ``P7Socket``.

## Cryptography Surface

- ``ECDH``: key agreement used during secure session establishment.
- ``ECDSA``: signature utilities and identity proof primitives.
- ``Cipher``: symmetric encryption and authenticated mode handling.
- ``Digest``: checksum and message authentication helpers.

## Server Identity And Trust

``ServerIdentity`` and related identity-provider protocols support TOFU-style identity persistence and verification.
Integrators should persist known server identities and alert users on unexpected fingerprint changes.

## Operational Recommendations

- Favor authenticated cipher suites when available.
- Keep identity verification enabled in production.
- Log handshake and auth failures with enough detail for audits.
