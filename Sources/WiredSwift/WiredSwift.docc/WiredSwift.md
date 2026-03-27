# ``WiredSwift``

Swift foundation for building Wired 3 clients and tools.

## Overview

`WiredSwift` exposes the protocol, networking, and crypto primitives used by Wired 3.
It is used by the `wired3` server, the macOS app wrapper, and standalone client tools.

This DocC catalog is organized to help integrators go from setup to production concerns.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:IntegrationNotes>
- <doc:ArchitectureOverview>

### API Surface

- <doc:ClientAPIOverview>
- ``Connection``
- ``AsyncConnection``
- ``BlockConnection``
- ``P7Socket``
- ``P7Message``

### Security And Protocol

- <doc:ProtocolAndSecurity>
- ``ECDH``
- ``ECDSA``
- ``Cipher``
- ``Digest``
- ``ServerIdentity``

### Operational Support

- ``Logger``
- ``WiredLogEntry``
- ``WiredServerEvent``
