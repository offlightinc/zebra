#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
REQUIRED_ZIG_VERSION="0.15.2"

cd "$PROJECT_DIR"

hash_stdin() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  else
    sha256sum | awk '{print $1}'
  fi
}

hash_file() {
  local path="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
  else
    sha256sum "$path" | awk '{print $1}'
  fi
}

lookup_pinned_ghosttykit_sha256() {
  local ghostty_sha="$1"
  local checksums_file="$2"
  awk -v sha="$ghostty_sha" '
    $1 == sha {
      print $2
      found = 1
      exit
    }
    END {
      if (!found) {
        exit 1
      }
    }
  ' "$checksums_file"
}

validate_bridge_header() {
  local path="$1"
  python3 - "$path" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text()
required = '#include "ghostty/include/ghostty.h"'
if required not in text:
    raise SystemExit(1)
PY
}

select_zig_for_ghosttykit() {
  if [[ -n "${CMUX_ZIG:-}" ]]; then
    if [[ ! -x "$CMUX_ZIG" ]]; then
      echo "error: CMUX_ZIG is not executable: $CMUX_ZIG" >&2
      return 1
    fi
    echo "$CMUX_ZIG"
    return 0
  fi

  # Ghostty documents a Zig 0.15.x link failure with Xcode 26.4 for the
  # official Zig tarball. Homebrew zig@0.15 carries the needed patch.
  local -a candidates=(
    "/opt/homebrew/opt/zig@0.15/bin/zig"
    "/usr/local/opt/zig@0.15/bin/zig"
    "$PROJECT_DIR/.tools/zig/$REQUIRED_ZIG_VERSION/zig"
  )
  local path_zig=""
  path_zig="$(command -v zig 2>/dev/null || true)"
  [[ -n "$path_zig" ]] && candidates+=("$path_zig")

  local candidate=""
  for candidate in "${candidates[@]}"; do
    [[ -x "$candidate" ]] || continue
    if [[ "$("$candidate" version 2>/dev/null || true)" == "$REQUIRED_ZIG_VERSION" ]]; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
}

require_pinned_zig() {
  local zig_bin="$1"
  local zig_version
  zig_version="$("$zig_bin" version)"
  if [[ "$zig_version" != "$REQUIRED_ZIG_VERSION" ]]; then
    echo "Error: GhosttyKit requires Zig $REQUIRED_ZIG_VERSION, found $zig_version at $zig_bin." >&2
    echo "Install repo-local Zig at .tools/zig/$REQUIRED_ZIG_VERSION/zig or set CMUX_ZIG." >&2
    return 1
  fi
  echo "==> Using Zig $zig_version at $zig_bin"
}

if [[ ! -d "$PROJECT_DIR/ghostty" ]]; then
  echo "error: ghostty submodule is missing. Run ./scripts/setup.sh first." >&2
  exit 1
fi

if [[ ! -f "$PROJECT_DIR/ghostty/include/ghostty.h" ]]; then
  echo "error: ghostty/include/ghostty.h is missing. Run ./scripts/setup.sh first." >&2
  exit 1
fi

if ! validate_bridge_header "$PROJECT_DIR/ghostty.h"; then
  echo "error: ghostty.h no longer points at ghostty/include/ghostty.h." >&2
  echo "Restore the bridge header so Xcode uses Ghostty's canonical C API." >&2
  exit 1
fi

GHOSTTY_SHA="$(git -C ghostty rev-parse HEAD)"
GHOSTTY_KEY="$GHOSTTY_SHA"
UNTRACKED_FILES="$(git -C ghostty ls-files --others --exclude-standard)"
if ! git -C ghostty diff --quiet --ignore-submodules=all HEAD -- || [[ -n "$UNTRACKED_FILES" ]]; then
  DIRTY_HASH="$(
    {
      printf 'head=%s\n' "$GHOSTTY_SHA"
      git -C ghostty diff --binary HEAD -- .
      if [[ -n "$UNTRACKED_FILES" ]]; then
        printf '\n--untracked--\n'
        while IFS= read -r path; do
          [[ -n "$path" ]] || continue
          printf 'path=%s\n' "$path"
          hash_file "$PROJECT_DIR/ghostty/$path"
        done <<< "$UNTRACKED_FILES"
      fi
    } | hash_stdin
  )"
  GHOSTTY_KEY="${GHOSTTY_SHA}-dirty-${DIRTY_HASH}"
fi

CACHE_ROOT="${CMUX_GHOSTTYKIT_CACHE_DIR:-$HOME/.cache/cmux/ghosttykit}"
CACHE_DIR="$CACHE_ROOT/$GHOSTTY_KEY"
CACHE_XCFRAMEWORK="$CACHE_DIR/GhosttyKit.xcframework"
LOCAL_XCFRAMEWORK="$PROJECT_DIR/ghostty/macos/GhosttyKit.xcframework"
LOCAL_KEY_STAMP="$LOCAL_XCFRAMEWORK/.ghostty_state_key"
LEGACY_LOCAL_SHA_STAMP="$LOCAL_XCFRAMEWORK/.ghostty_sha"
LOCK_DIR="$CACHE_ROOT/$GHOSTTY_KEY.lock"
GHOSTTYKIT_CHECKSUMS_FILE="${CMUX_GHOSTTYKIT_CHECKSUMS_FILE:-$SCRIPT_DIR/ghosttykit-checksums.txt}"
GHOSTTYKIT_ARCHIVE_VALIDATOR="${CMUX_GHOSTTYKIT_ARCHIVE_VALIDATOR:-$SCRIPT_DIR/validate-xcframework-archive.py}"

mkdir -p "$CACHE_ROOT"

echo "==> Ghostty build key: $GHOSTTY_KEY"

LOCK_TIMEOUT=300
LOCK_START=$SECONDS
while ! mkdir "$LOCK_DIR" 2>/dev/null; do
  if (( SECONDS - LOCK_START > LOCK_TIMEOUT )); then
    echo "==> Lock stale (>${LOCK_TIMEOUT}s), removing and retrying..."
    rmdir "$LOCK_DIR" 2>/dev/null || rm -rf "$LOCK_DIR"
    continue
  fi
  echo "==> Waiting for GhosttyKit cache lock for $GHOSTTY_KEY..."
  sleep 1
done
trap 'rmdir "$LOCK_DIR" >/dev/null 2>&1 || true' EXIT

try_fetch_prebuilt_xcframework() {
  # Only attempt when Ghostty submodule is clean — dirty trees won't match any
  # published release. Opt-out via CMUX_GHOSTTYKIT_NO_PREBUILT=1.
  #
  # Trust model: only install prebuilt artifacts whose SHA256 is pinned in the
  # reviewed checksum manifest for the current ghostty submodule commit.
  # Unpinned or mismatched artifacts fall back to a local ReleaseFast build.
  if [[ "$GHOSTTY_KEY" != "$GHOSTTY_SHA" ]]; then
    return 1
  fi
  if [[ "${CMUX_GHOSTTYKIT_NO_PREBUILT:-0}" == "1" ]]; then
    return 1
  fi
  if ! command -v curl >/dev/null 2>&1; then
    return 1
  fi

  local url="https://github.com/manaflow-ai/ghostty/releases/download/xcframework-${GHOSTTY_SHA}/GhosttyKit.xcframework.tar.gz"
  if [[ ! -f "$GHOSTTYKIT_CHECKSUMS_FILE" ]]; then
    echo "==> Missing GhosttyKit checksum manifest; falling back to local build." >&2
    return 1
  fi

  local expected_sha
  if ! expected_sha="$(lookup_pinned_ghosttykit_sha256 "$GHOSTTY_SHA" "$GHOSTTYKIT_CHECKSUMS_FILE" 2>/dev/null)"; then
    echo "==> No pinned GhosttyKit checksum for ${GHOSTTY_SHA:0:12}; falling back to local build." >&2
    return 1
  fi

  local tmp_dir tmp_tar tmp_extract actual_sha
  tmp_dir="$(mktemp -d "$CACHE_ROOT/.ghosttykit-prebuilt.XXXXXX")"
  tmp_tar="$tmp_dir/GhosttyKit.xcframework.tar.gz"
  tmp_extract="$tmp_dir/extract"
  mkdir -p "$tmp_extract"
  echo "==> Fetching prebuilt GhosttyKit.xcframework for ${GHOSTTY_SHA:0:12}..."
  if ! curl -fSL --connect-timeout 10 --max-time 300 --retry 3 --retry-delay 2 --retry-all-errors -o "$tmp_tar" "$url"; then
    rm -rf "$tmp_dir"
    echo "==> Prebuilt xcframework not available; falling back to local build."
    return 1
  fi

  actual_sha="$(hash_file "$tmp_tar")"
  if [[ "$actual_sha" != "$expected_sha" ]]; then
    rm -rf "$tmp_dir"
    echo "==> Prebuilt xcframework checksum mismatch; falling back to local build." >&2
    echo "    expected: $expected_sha" >&2
    echo "    actual:   $actual_sha" >&2
    return 1
  fi

  if ! python3 "$GHOSTTYKIT_ARCHIVE_VALIDATOR" "$tmp_tar"; then
    rm -rf "$tmp_dir"
    echo "==> Prebuilt xcframework archive failed validation; falling back to local build." >&2
    return 1
  fi

  if ! tar --no-same-owner -xzf "$tmp_tar" -C "$tmp_extract"; then
    rm -rf "$tmp_dir"
    echo "==> Failed to extract verified prebuilt xcframework; falling back to local build." >&2
    return 1
  fi

  local extracted="$tmp_extract/GhosttyKit.xcframework"
  if [[ ! -d "$extracted" ]]; then
    rm -rf "$tmp_dir"
    echo "==> Prebuilt archive did not contain GhosttyKit.xcframework; falling back." >&2
    return 1
  fi

  mkdir -p "$(dirname "$LOCAL_XCFRAMEWORK")"
  rm -rf "$LOCAL_XCFRAMEWORK"
  mv "$extracted" "$LOCAL_XCFRAMEWORK"
  rm -rf "$tmp_dir"
  echo "$GHOSTTY_KEY" > "$LOCAL_KEY_STAMP"
  echo "$GHOSTTY_SHA" > "$LEGACY_LOCAL_SHA_STAMP"
  return 0
}

if [[ -d "$CACHE_XCFRAMEWORK" ]]; then
  echo "==> Reusing cached GhosttyKit.xcframework"
else
  LOCAL_KEY=""
  if [[ -f "$LOCAL_KEY_STAMP" ]]; then
    LOCAL_KEY="$(cat "$LOCAL_KEY_STAMP")"
  elif [[ -f "$LEGACY_LOCAL_SHA_STAMP" ]]; then
    LOCAL_KEY="$(cat "$LEGACY_LOCAL_SHA_STAMP")"
  fi

  if [[ -d "$LOCAL_XCFRAMEWORK" && "$LOCAL_KEY" == "$GHOSTTY_KEY" ]]; then
    echo "==> Seeding cache from existing local GhosttyKit.xcframework (build key matches)"
  elif [[ "${CMUX_SKIP_ZIG_BUILD:-}" == "1" && -d "$LOCAL_XCFRAMEWORK" ]]; then
    echo "==> Reusing existing local GhosttyKit.xcframework (CMUX_SKIP_ZIG_BUILD=1)"
  elif try_fetch_prebuilt_xcframework; then
    echo "==> Seeding cache from prebuilt GhosttyKit.xcframework"
  elif [[ "${CMUX_SKIP_ZIG_BUILD:-}" == "1" ]]; then
    echo "Error: CMUX_SKIP_ZIG_BUILD=1 but no reusable GhosttyKit.xcframework exists." >&2
    echo "Unset CMUX_SKIP_ZIG_BUILD or install the repo-required Zig version to build GhosttyKit." >&2
    exit 1
  else
    ZIG_BIN="$(select_zig_for_ghosttykit || true)"
    if [[ -z "$ZIG_BIN" ]]; then
      echo "Error: zig is not installed." >&2
      echo "Install repo-local Zig at .tools/zig/$REQUIRED_ZIG_VERSION/zig or set CMUX_ZIG." >&2
      exit 1
    fi
    if ! require_pinned_zig "$ZIG_BIN"; then
      exit 1
    fi
    echo "==> Building GhosttyKit.xcframework (this may take a few minutes)..."
    (
      cd ghostty
      "$ZIG_BIN" build -Demit-xcframework=true -Dxcframework-target=universal -Doptimize=ReleaseFast
    )
    echo "$GHOSTTY_KEY" > "$LOCAL_KEY_STAMP"
    echo "$GHOSTTY_SHA" > "$LEGACY_LOCAL_SHA_STAMP"
  fi

  if [[ ! -d "$LOCAL_XCFRAMEWORK" ]]; then
    echo "Error: GhosttyKit.xcframework not found at $LOCAL_XCFRAMEWORK" >&2
    exit 1
  fi

  TMP_DIR="$(mktemp -d "$CACHE_ROOT/.ghosttykit-tmp.XXXXXX")"
  mkdir -p "$CACHE_DIR"
  cp -R "$LOCAL_XCFRAMEWORK" "$TMP_DIR/GhosttyKit.xcframework"
  rm -rf "$CACHE_XCFRAMEWORK"
  mv "$TMP_DIR/GhosttyKit.xcframework" "$CACHE_XCFRAMEWORK"
  rmdir "$TMP_DIR"
  echo "==> Cached GhosttyKit.xcframework at $CACHE_XCFRAMEWORK"
fi

MACOS_ARCHIVE="$CACHE_XCFRAMEWORK/macos-arm64_x86_64/libghostty.a"
if [[ -f "$MACOS_ARCHIVE" ]]; then
  # Xcode 26 can fail to resolve symbols from Ghostty's universal static archive
  # until its ranlib index is refreshed after reuse or copy.
  echo "==> Refreshing libghostty archive index..."
  if ! command -v xcrun >/dev/null 2>&1; then
    echo "error: xcrun is required to refresh libghostty archive index." >&2
    exit 1
  fi
  if ! XCODE_RANLIB="$(xcrun --find ranlib 2>/dev/null)"; then
    echo "error: could not locate ranlib via xcrun." >&2
    exit 1
  fi
  "$XCODE_RANLIB" "$MACOS_ARCHIVE"
fi

echo "==> Creating symlink for GhosttyKit.xcframework..."
ln -sfn "$CACHE_XCFRAMEWORK" GhosttyKit.xcframework
