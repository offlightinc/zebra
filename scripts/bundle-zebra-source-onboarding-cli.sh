#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <Zebra.app>" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="$1"
PRODUCT="zebra-slack-source-onboarding"
ARM64_SCRATCH="$REPO_ROOT/Packages/ZebraVault/.build/$PRODUCT-arm64"
X86_64_SCRATCH="$REPO_ROOT/Packages/ZebraVault/.build/$PRODUCT-x86_64"

if [[ ! -d "$APP_PATH/Contents/Resources" ]]; then
  echo "error: app resources not found: $APP_PATH" >&2
  exit 1
fi

build_architecture() {
  local architecture="$1"
  local scratch_path="$2"
  local triple="${architecture}-apple-macosx14.0"

  swift build \
    --package-path "$REPO_ROOT/Packages/ZebraVault" \
    --scratch-path "$scratch_path" \
    --configuration release \
    --triple "$triple" \
    --product "$PRODUCT" >&2

  swift build \
    --package-path "$REPO_ROOT/Packages/ZebraVault" \
    --scratch-path "$scratch_path" \
    --configuration release \
    --triple "$triple" \
    --show-bin-path
}

ARM64_BIN_PATH="$(build_architecture arm64 "$ARM64_SCRATCH")"
X86_64_BIN_PATH="$(build_architecture x86_64 "$X86_64_SCRATCH")"
DESTINATION_DIR="$APP_PATH/Contents/Resources/bin"
ARM64_SOURCE="$ARM64_BIN_PATH/$PRODUCT"
X86_64_SOURCE="$X86_64_BIN_PATH/$PRODUCT"

for source in "$ARM64_SOURCE" "$X86_64_SOURCE"; do
  if [[ ! -x "$source" ]]; then
    echo "error: built Slack onboarding CLI not found: $source" >&2
    exit 1
  fi
done

mkdir -p "$DESTINATION_DIR"
/usr/bin/lipo -create "$ARM64_SOURCE" "$X86_64_SOURCE" -output "$DESTINATION_DIR/$PRODUCT"
chmod 755 "$DESTINATION_DIR/$PRODUCT"

ARCHITECTURES="$(/usr/bin/lipo -archs "$DESTINATION_DIR/$PRODUCT")"
if [[ "$ARCHITECTURES" != *arm64* || "$ARCHITECTURES" != *x86_64* ]]; then
  echo "error: bundled Slack onboarding CLI is not universal: $ARCHITECTURES" >&2
  exit 1
fi
