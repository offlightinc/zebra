#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo "==> Initializing submodules..."
git submodule update --init --recursive

echo "==> Checking for zig..."
if ! command -v zig &> /dev/null; then
    echo "Error: zig is not installed."
    echo "Install via: brew install zig"
    exit 1
fi

"$SCRIPT_DIR/ensure-ghosttykit.sh"

# Point git at the shared hooks dir so every clone picks up the Phase 4
# touchpoint guard. Idempotent — re-running setup.sh is safe.
echo "==> Wiring git hooks (.githooks)"
git -C "$PROJECT_DIR" config core.hooksPath .githooks

echo "==> Setup complete!"
echo ""
echo "You can now build and run the app:"
echo "  ./scripts/reload.sh --tag first-run"
