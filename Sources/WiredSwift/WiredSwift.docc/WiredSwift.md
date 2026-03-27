# ``WiredSwift``

Swift foundation for building Wired 3 clients and tools.

## Overview

`WiredSwift` exposes the protocol, networking, and crypto primitives used by Wired 3.
It is used by the `wired3` server, the macOS app wrapper, and standalone client tools.

This DocC catalog is intentionally compact: a small set of guides plus symbol-level API documentation.

## Topics

### Start Here

- <doc:GettingStarted>
- <doc:ConnectionPatterns>
- <doc:Operations>

### Security And Protocol

- <doc:ProtocolAndSecurity>
- ``P7Socket``
- ``P7Message``
- ``ECDH``
- ``ECDSA``
- ``Cipher``
- ``Digest``
- ``ServerIdentity``

### Architecture

- <doc:ArchitectureOverview>

### Core APIs

- ``Connection``
- ``AsyncConnection``
- ``BlockConnection``
- ``P7Spec``
- ``Url``
- ``Logger``
