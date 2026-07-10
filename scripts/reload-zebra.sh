#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TAG=""
DERIVED_DATA=""
LAUNCH=0
FORWARD_ARGS=()

usage() {
  cat <<'EOF'
Usage: ./scripts/reload-zebra.sh --tag <name> [options]

Builds the normal isolated Debug app, then applies the Zebra-owned brand overlay.
The resulting app is named "Zebra DEV <tag>" and uses an isolated Zebra debug
bundle identifier. All reload.sh options except --name and --bundle-id are accepted.
EOF
}

sanitize_bundle() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/./g; s/^\.+//; s/\.+$//; s/\.+/./g'
}

sanitize_path() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      TAG="${2:-}"
      [[ -n "$TAG" ]] || { echo "error: --tag requires a value" >&2; exit 1; }
      FORWARD_ARGS+=("$1" "$2")
      shift 2
      ;;
    --derived-data)
      DERIVED_DATA="${2:-}"
      [[ -n "$DERIVED_DATA" ]] || { echo "error: --derived-data requires a value" >&2; exit 1; }
      FORWARD_ARGS+=("$1" "$2")
      shift 2
      ;;
    --launch)
      LAUNCH=1
      shift
      ;;
    --name|--bundle-id)
      echo "error: $1 is managed by the Zebra Debug overlay" >&2
      exit 1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      FORWARD_ARGS+=("$1")
      shift
      ;;
  esac
done

if [[ -z "$TAG" ]]; then
  echo "error: --tag is required" >&2
  usage >&2
  exit 1
fi

TAG_SLUG="$(sanitize_path "$TAG")"
TAG_ID="$(sanitize_bundle "$TAG")"
[[ -n "$TAG_SLUG" ]] || TAG_SLUG="agent"
[[ -n "$TAG_ID" ]] || TAG_ID="agent"

APP_NAME="Zebra DEV ${TAG_SLUG}"
BUNDLE_ID="com.offlight.zebra.debug.${TAG_ID}"
if [[ -z "$DERIVED_DATA" ]]; then
  DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData/cmux-${TAG_SLUG}"
fi

cd "$REPO_ROOT"
"$SCRIPT_DIR/reload.sh" \
  "${FORWARD_ARGS[@]}" \
  --name "$APP_NAME" \
  --bundle-id "$BUNDLE_ID"

APP_PATH="${DERIVED_DATA}/Build/Products/Debug/${APP_NAME}.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "error: Zebra Debug app not found: $APP_PATH" >&2
  exit 1
fi

echo "==> applying Zebra Debug localization overlay"
python3 "$SCRIPT_DIR/apply-zebra-localization-overlay.py" \
  "$APP_PATH" \
  --overlay "$SCRIPT_DIR/zebra-localization-overlay.json"

/usr/bin/codesign \
  --force \
  --sign - \
  --timestamp=none \
  --generate-entitlement-der \
  "$APP_PATH"
/usr/bin/codesign --verify --deep --strict "$APP_PATH"

# Keep existing tag-bound CLI tooling working without changing upstream helpers.
COMPAT_APP_PATH="${DERIVED_DATA}/Build/Products/Debug/cmux DEV ${TAG_SLUG}.app"
rm -rf "$COMPAT_APP_PATH"
ln -s "${APP_NAME}.app" "$COMPAT_APP_PATH"

if [[ "$LAUNCH" -eq 1 ]]; then
  /usr/bin/env \
    -u CMUX_SOCKET_PATH \
    -u CMUX_WORKSPACE_ID \
    -u CMUX_SURFACE_ID \
    -u CMUX_TAB_ID \
    -u CMUX_PANEL_ID \
    -u CMUXD_UNIX_PATH \
    -u CMUX_TAG \
    -u CMUX_DEBUG_LOG \
    -u CMUX_BUNDLE_ID \
    /usr/bin/open "$APP_PATH"
fi

echo
echo "Zebra Debug app ready."
echo "App path:"
echo "  $APP_PATH"
echo "Bundle id:"
echo "  $BUNDLE_ID"
