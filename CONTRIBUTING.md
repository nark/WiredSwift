# Contributing to WiredSwift

Thank you for your interest in contributing to WiredSwift / wired3.
This document covers setup, conventions, and the PR workflow.

---

## Table of Contents

- [Prerequisites](#prerequisites)
- [Getting started](#getting-started)
- [Code style](#code-style)
- [Commit conventions](#commit-conventions)
- [Pull request workflow](#pull-request-workflow)
- [Architecture overview](#architecture-overview)

---

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Swift | 5.9+ | [swift.org](https://swift.org/download/) |
| SwiftLint | 0.63+ | `brew install swiftlint` |
| Git | any | system |

SwiftLint is also installed automatically in CI (GitHub Actions).

---

## Getting started

```bash
git clone https://github.com/nark/WiredSwift.git
cd WiredSwift

# Install the pre-commit hook (runs SwiftLint before each commit)
bash Scripts/install-hooks.sh

# Build the server
swift build --product wired3

# Run the test suite
swift test
```

---

## Code style

This project uses **SwiftLint** to enforce a consistent code style.
Configuration is in `.swiftlint.yml` at the project root.

### Quick reference

| Convention | Rule |
|-----------|------|
| Indentation | 4 spaces (no tabs) |
| Line length | 160 chars soft / 200 hard |
| Identifiers | `camelCase`; GRDB column properties may use `snake_case` |
| Short names | `db`, `t`, `c` are allowed in GRDB closures; single-char vars generate a warning |
| `force_try` | Avoid — produces a warning; justify with a comment if unavoidable |

### Running the linter

```bash
# Check for violations
swiftlint lint

# Auto-fix stylistic violations
swiftlint --fix
```

### Building documentation (DocC)

```bash
# Validate DocC generation for the WiredSwift module
swift package generate-documentation --target WiredSwift

# Build static output for hosting (for example GitHub Pages)
swift package --allow-writing-to-directory ./docs \
  generate-documentation \
  --target WiredSwift \
  --output-path ./docs \
  --transform-for-static-hosting \
  --hosting-base-path WiredSwift
```

CI fails if any **error**-level violation is introduced.
Warnings are reported as annotations on pull requests but do not block merges.

### Known technical debt

Several large types (`ServerController`, `BoardsController`, `P7Socket`, …) carry
a `// swiftlint:disable` annotation with a `// TODO:` note. These are pre-existing
structural issues tracked for future refactoring — do not add new `swiftlint:disable`
lines without a corresponding issue or TODO comment explaining why.

---

## Commit conventions

This project follows [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <short summary>
```

Common types: `feat`, `fix`, `test`, `refactor`, `chore`, `docs`, `perf`.
Scope examples: `p7`, `auth`, `chat`, `files`, `lint`, `ci`.

**Examples:**
```
feat(chat): add rate limiting for public chat creation
fix(p7): reject messages with field length > 16 MB
test(auth): cover brute-force lockout path
chore(lint): suppress type_body_length in FilesController
```

---

## Pull request workflow

1. Fork the repository and create a branch from `master`:
   ```bash
   git checkout -b feat/my-feature master
   ```
2. Make your changes and ensure the pre-commit hook passes.
3. Run the full test suite: `swift test`
4. Open a PR against `master`.  CI runs lint → build → tests.
5. Address review comments; the PR is merged once CI is green.

> **Branch protection**: never commit directly to `main` or `master`.

---

## Architecture overview

| Target | Role |
|--------|------|
| `WiredSwift` | Reusable library — P7 protocol parser, crypto, connection abstractions |
| `wired3` | Server daemon — auth, chat, files, boards, transfers |
| `WiredServerApp` | macOS GUI wrapper around `wired3` |

Key directories inside `WiredSwift`:

```
Sources/WiredSwift/
├── P7/        Protocol parser and socket (P7Message, P7Socket, P7Spec)
├── Crypto/    ECDSA, ECDH, ciphers, digests
├── Network/   Connection, BlockConnection, URL helpers
└── Core/      Logger, Config, errors, server events
```

The binary protocol format is defined in `Sources/WiredSwift/Resources/wired.xml`
(P7 spec — do not modify this file).
