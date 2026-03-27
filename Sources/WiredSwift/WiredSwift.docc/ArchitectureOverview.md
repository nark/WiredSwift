# Architecture Overview

## Project Roles

This repository contains three major deliverables:

- `WiredSwift`: reusable client/server protocol library.
- `wired3`: server daemon built on top of `WiredSwift`.
- `WiredServerApp`: macOS app wrapper for operating `wired3` locally.

## `WiredSwift` Layers

- `P7`: protocol model, symbol definitions, message parsing and framing.
- `Network`: transport abstraction and connection lifecycle.
- `Crypto`: cipher suites, key agreement, signatures, and digest support.
- `Core` and `Data`: shared runtime types, logging, config, and models.

## Typical Message Path

1. App code creates or reacts to a ``P7Message``.
2. ``Connection`` or ``P7Socket`` serializes and transmits bytes.
3. Protocol layer parses inbound payload into strongly-typed structures.
4. App-level handlers decide business behavior.

## Design Principles

- Protocol implementation is transport-aware but app-agnostic.
- Security primitives are explicit and configurable.
- Backward-compatible API surface is favored for integrators.
