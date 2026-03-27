# Client API Overview

## Connection Types

### ``Connection``

Use when you want full control over connection lifecycle and message handling.

### ``AsyncConnection``

Use in async/await-first codebases to integrate naturally with Swift concurrency.

### ``BlockConnection``

Use when your application architecture is callback/delegate oriented.

## Protocol Types

### ``P7Socket``

Low-level transport and framing implementation for Wired P7 messages.

### ``P7Message``

Primary message container used for commands, replies, and event notifications.

## Runtime Observability

- ``Logger`` for log output and structured log records.
- ``WiredServerEvent`` and ``WiredLogEntry`` for event-driven diagnostics.

## Choosing Abstractions

Start high-level (`AsyncConnection`/`Connection`) unless you specifically need custom framing or protocol-level intervention.
