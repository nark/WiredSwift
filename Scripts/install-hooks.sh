#!/usr/bin/env bash
# install-hooks.sh — Install the WiredSwift git pre-commit hook.
# Usage: bash Scripts/install-hooks.sh

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
HOOKS_DIR="$REPO_ROOT/.git/hooks"
HOOK="$HOOKS_DIR/pre-commit"

# ── Verify SwiftLint is available ─────────────────────────────────────
if ! command -v swiftlint &>/dev/null; then
    echo "Error: swiftlint not found."
    echo "Install it with: brew install swiftlint"
    exit 1
fi

# ── Write the pre-commit hook ─────────────────────────────────────────
cat > "$HOOK" <<'EOF'
#!/usr/bin/env bash
# Pre-commit hook: run SwiftLint on staged Swift files.
# Blocks the commit if any error-level violation is found.

set -euo pipefail

if ! command -v swiftlint &>/dev/null; then
    echo "warning: swiftlint not found — skipping lint check"
    exit 0
fi

STAGED=$(git diff --cached --name-only --diff-filter=ACM | grep '\.swift$' || true)

if [[ -z "$STAGED" ]]; then
    exit 0
fi

echo "SwiftLint: checking $(echo "$STAGED" | wc -l | tr -d ' ') staged Swift file(s)…"

# Run SwiftLint only on staged files
echo "$STAGED" | xargs swiftlint lint --use-stdin <<< "" 2>/dev/null || \
    swiftlint lint $STAGED

EXIT_CODE=$?
if [[ $EXIT_CODE -ne 0 ]]; then
    echo ""
    echo "SwiftLint found errors. Fix them or run 'swiftlint --fix' before committing."
    exit 1
fi

exit 0
EOF

chmod +x "$HOOK"

echo "Pre-commit hook installed at $HOOK"
echo "It will run SwiftLint on staged Swift files before each commit."
