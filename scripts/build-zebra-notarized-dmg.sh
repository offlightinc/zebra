#!/usr/bin/env bash
set -euo pipefail

# Zebra release overlay for the cmux upstream project.
# Keeps cmux.xcodeproj defaults untouched, but builds/signs/notarizes as Zebra.

APP_NAME="${ZEBRA_APP_NAME:-Zebra}"
BUNDLE_ID="${ZEBRA_BUNDLE_ID:-com.offlight.zebra}"
DERIVED_DATA="${ZEBRA_DERIVED_DATA:-build-zebra-release}"
DIST_DIR="${ZEBRA_DIST_DIR:-dist}"
DMG_PATH="${ZEBRA_DMG_PATH:-${DIST_DIR}/Zebra.dmg}"
SIGNING_IDENTITY="${APPLE_SIGNING_IDENTITY:-Developer ID Application: OFFLIGHT Inc. (3V648FU6PC)}"
APP_ENTITLEMENTS="${ZEBRA_APP_ENTITLEMENTS:-zebra.release.entitlements}"
HELPER_ENTITLEMENTS="${ZEBRA_HELPER_ENTITLEMENTS:-cmux-helper.entitlements}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
ZEBRA_POSTHOG_INFO_KEY="ZebraPostHogProjectToken"
ZEBRA_POSTHOG_PLACEHOLDER="REPLACE_WITH_ZEBRA_POSTHOG_PROJECT_TOKEN"
SKIP_BUILD=0
SKIP_SIGN=0
SKIP_NOTARIZE=0
REQUIRE_POSTHOG_KEY=0
DISABLE_POSTHOG=0
CLEAN_BUILD=0

usage() {
  cat <<'EOF'
Usage: scripts/build-zebra-notarized-dmg.sh [options]

Builds a Developer ID signed Zebra.app and creates a DMG. Notarization runs when
--notary-profile is supplied, or when NOTARY_PROFILE is set.

Options:
  --notary-profile <name>  Keychain profile created by xcrun notarytool store-credentials.
  --skip-build             Reuse the existing build-zebra-release app.
  --clean-build            Delete derived data before building. The default preserves build caches.
  --skip-sign              Skip app and DMG signing for local packaging tests.
  --skip-notarize          Create a signed DMG without notarizing it.
  --require-posthog-key    Fail when ZEBRA_POSTHOG_API_KEY is not set.
  --disable-posthog        Build successfully with Zebra telemetry disabled.
  -h, --help               Show this help.

Environment overrides:
  ZEBRA_APP_NAME           Default: Zebra
  ZEBRA_BUNDLE_ID          Default: com.offlight.zebra
  APPLE_SIGNING_IDENTITY   Default: Developer ID Application: OFFLIGHT Inc. (3V648FU6PC)
  ZEBRA_APP_ENTITLEMENTS   Default: zebra.release.entitlements
  ZEBRA_DERIVED_DATA       Default: build-zebra-release
  ZEBRA_DMG_PATH           Default: dist/Zebra.dmg
  ZEBRA_POSTHOG_API_KEY    Optional local/release PostHog project token.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --notary-profile)
      NOTARY_PROFILE="${2:-}"
      if [[ -z "$NOTARY_PROFILE" ]]; then
        echo "error: --notary-profile requires a value" >&2
        exit 1
      fi
      shift 2
      ;;
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    --clean-build)
      CLEAN_BUILD=1
      shift
      ;;
    --skip-sign)
      SKIP_SIGN=1
      SKIP_NOTARIZE=1
      shift
      ;;
    --skip-notarize)
      SKIP_NOTARIZE=1
      shift
      ;;
    --require-posthog-key)
      REQUIRE_POSTHOG_KEY=1
      shift
      ;;
    --disable-posthog)
      DISABLE_POSTHOG=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown option $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ "$DISABLE_POSTHOG" -eq 1 && "$REQUIRE_POSTHOG_KEY" -eq 1 ]]; then
  echo "error: --disable-posthog cannot be combined with --require-posthog-key" >&2
  exit 1
fi

ZEBRA_POSTHOG_PROJECT_TOKEN="${ZEBRA_POSTHOG_API_KEY:-}"
if [[ "$DISABLE_POSTHOG" -eq 1 ]]; then
  ZEBRA_POSTHOG_PROJECT_TOKEN=""
fi
if [[ "$REQUIRE_POSTHOG_KEY" -eq 1 && -z "$ZEBRA_POSTHOG_PROJECT_TOKEN" ]]; then
  echo "error: ZEBRA_POSTHOG_API_KEY is required for this build" >&2
  exit 1
fi

require_tool() {
  command -v "$1" >/dev/null || {
    echo "error: missing required tool: $1" >&2
    exit 1
  }
}

require_create_dmg() {
  local help
  local version
  help="$(create-dmg --help 2>&1 || true)"
  version="$(create-dmg --version 2>&1 || true)"

  if [[ "$help" != *"<output_name.dmg> <source_folder>"* ]] \
    || [[ "$help" != *"--app-drop-link"* ]] \
    || [[ "$help" != *"--codesign"* ]]; then
    cat >&2 <<EOF
error: unsupported create-dmg command.
Expected the shell create-dmg tool that supports:
  create-dmg [options] <output_name.dmg> <source_folder>
  --app-drop-link
  --codesign

Found:
${version:-$help}
EOF
    exit 1
  fi
}

required_zig_version="0.15.2"

zig_version() {
  "$1" version 2>/dev/null || true
}

find_compatible_zig() {
  local candidates=()
  local candidate

  if [[ -n "${CMUX_ZIG:-}" ]]; then
    candidates+=("$CMUX_ZIG")
  fi
  candidates+=(
    "/opt/homebrew/opt/zig@0.15/bin/zig"
    "/usr/local/opt/zig@0.15/bin/zig"
    "$PWD/.tools/zig/$required_zig_version/zig"
  )
  candidate="$(command -v zig 2>/dev/null || true)"
  if [[ -n "$candidate" ]]; then
    candidates+=("$candidate")
  fi

  for candidate in "${candidates[@]}"; do
    if [[ -x "$candidate" && "$(zig_version "$candidate")" == "$required_zig_version" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

preflight_build_environment() {
  local zig_path

  if ! zig_path="$(find_compatible_zig)"; then
    cat >&2 <<EOF
error: Zig $required_zig_version is required before starting the Zebra Release build.
Install the Xcode 26-compatible Homebrew formula with:
  brew install zig@0.15
Alternatively install repo-local Zig at .tools/zig/$required_zig_version/zig or set CMUX_ZIG.
EOF
    exit 1
  fi
  echo "==> preflight: Zig $required_zig_version at $zig_path"

  if ! xcodebuild -showComponent MetalToolchain -json 2>/dev/null \
    | grep -Fq '"status" : "installed"'; then
    cat >&2 <<'EOF'
error: the Xcode Metal Toolchain is required before starting the Zebra Release build.
Install it with:
  xcodebuild -downloadComponent MetalToolchain
EOF
    exit 1
  fi
  echo "==> preflight: Metal Toolchain available"
}

preflight_signing_identity() {
  if [[ "$SKIP_SIGN" -eq 1 || "$SIGNING_IDENTITY" == "-" ]]; then
    return
  fi

  if ! security find-identity -v -p codesigning 2>/dev/null | grep -Fq "$SIGNING_IDENTITY"; then
    cat >&2 <<EOF
error: signing identity not found: $SIGNING_IDENTITY
For an ad-hoc local test build, run:
  APPLE_SIGNING_IDENTITY=- ./scripts/build-zebra-notarized-dmg.sh --skip-notarize
EOF
    exit 1
  fi
  echo "==> preflight: signing identity available"
}

sign_path() {
  local path="$1"
  local entitlements="$2"
  /usr/bin/codesign \
    --force \
    --options runtime \
    --timestamp \
    --sign "$SIGNING_IDENTITY" \
    --entitlements "$entitlements" \
    "$path"
}

create_dmg_with_hdiutil() {
  local app_path="$1"
  local dmg_path="$2"
  local temp_dir
  local mount_path
  local work_dmg
  local size_kb
  local size_mb
  local attached=0

  temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/zebra-dmg.XXXXXX")"
  mount_path="${temp_dir}/mount"
  work_dmg="${temp_dir}/${APP_NAME}-work.dmg"
  mkdir -p "$mount_path"

  size_kb="$(du -sk "$app_path" | awk '{print $1}')"
  size_mb=$((size_kb / 1024 + 160))

  cleanup() {
    trap - RETURN
    if [[ "${attached:-0}" -eq 1 && -n "${mount_path:-}" ]]; then
      hdiutil detach "$mount_path" >/dev/null 2>&1 || true
    fi
    if [[ -n "${temp_dir:-}" ]]; then
      rm -rf "$temp_dir"
    fi
  }
  trap cleanup RETURN

  hdiutil create -size "${size_mb}m" -fs APFS -volname "$APP_NAME" -ov "$work_dmg"
  hdiutil attach "$work_dmg" -mountpoint "$mount_path" -nobrowse
  attached=1
  ditto "$app_path" "${mount_path}/${APP_NAME}.app"
  ln -s /Applications "${mount_path}/Applications"
  if [[ "$SKIP_SIGN" -eq 0 ]]; then
    /usr/bin/codesign --verify --deep --strict --verbose=2 "${mount_path}/${APP_NAME}.app"
  fi
  hdiutil detach "$mount_path"
  attached=0
  hdiutil convert "$work_dmg" -format UDZO -o "$dmg_path" -ov
}

create_zebra_dmg() {
  local app_path="$1"
  local dmg_path="$2"
  local staging_dir
  local create_dmg_args

  staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/zebra-dmg-stage.XXXXXX")"

  ditto "$app_path" "${staging_dir}/${APP_NAME}.app"

  create_dmg_args=(
    --volname "$APP_NAME"
    --window-size 560 360
    --icon-size 128
    --icon "${APP_NAME}.app" 150 170
    --hide-extension "${APP_NAME}.app"
    --app-drop-link 410 170
  )

  if [[ "$SKIP_SIGN" -eq 0 ]]; then
    create_dmg_args+=(--codesign "$SIGNING_IDENTITY")
  fi

  if ! create-dmg "${create_dmg_args[@]}" "$dmg_path" "$staging_dir"; then
    rm -rf "$staging_dir"
    echo "==> create-dmg failed; retrying with hdiutil fallback"
    create_dmg_with_hdiutil "$app_path" "$dmg_path"
    return
  fi

  rm -rf "$staging_dir"
}

require_tool xcodebuild
require_tool codesign
require_tool ditto
require_tool python3
require_tool xcrun
require_tool create-dmg
require_tool hdiutil
require_create_dmg
preflight_signing_identity

if [[ "$SKIP_BUILD" -eq 0 ]]; then
  preflight_build_environment
fi

if [[ ! -f "$APP_ENTITLEMENTS" ]]; then
  echo "error: app entitlements not found: $APP_ENTITLEMENTS" >&2
  exit 1
fi
if [[ ! -f "$HELPER_ENTITLEMENTS" ]]; then
  echo "error: helper entitlements not found: $HELPER_ENTITLEMENTS" >&2
  exit 1
fi

BUILD_APP_PATH="${DERIVED_DATA}/Build/Products/Release/cmux.app"
APP_PATH="${DERIVED_DATA}/Build/Products/Release/${APP_NAME}.app"

if [[ "$SKIP_BUILD" -eq 0 ]]; then
  echo "==> building upstream cmux.app for ${APP_NAME}"
  if [[ "$CLEAN_BUILD" -eq 1 ]]; then
    echo "==> removing derived data for clean build"
    rm -rf "$DERIVED_DATA"
  else
    echo "==> preserving derived data for incremental build"
  fi
  xcodebuild \
    -project cmux.xcodeproj \
    -scheme cmux \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    -destination 'generic/platform=macOS' \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO \
    build
fi

if [[ ! -d "$BUILD_APP_PATH" ]]; then
  echo "error: built app bundle not found: $BUILD_APP_PATH" >&2
  exit 1
fi

if [[ "$BUILD_APP_PATH" != "$APP_PATH" ]]; then
  rm -rf "$APP_PATH"
  cp -R "$BUILD_APP_PATH" "$APP_PATH"
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: app bundle not found: $APP_PATH" >&2
  exit 1
fi

INFO_PLIST="$APP_PATH/Contents/Info.plist"
if [[ ! -f "$INFO_PLIST" ]]; then
  echo "error: Info.plist not found: $INFO_PLIST" >&2
  exit 1
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$INFO_PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleName string $APP_NAME" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $APP_NAME" "$INFO_PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $APP_NAME" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$INFO_PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string $BUNDLE_ID" "$INFO_PLIST"

if [[ -n "$ZEBRA_POSTHOG_PROJECT_TOKEN" ]]; then
  /usr/libexec/PlistBuddy -c "Set :${ZEBRA_POSTHOG_INFO_KEY} $ZEBRA_POSTHOG_PROJECT_TOKEN" "$INFO_PLIST" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :${ZEBRA_POSTHOG_INFO_KEY} string $ZEBRA_POSTHOG_PROJECT_TOKEN" "$INFO_PLIST"
  echo "==> Zebra PostHog project token injected"
else
  /usr/libexec/PlistBuddy -c "Set :${ZEBRA_POSTHOG_INFO_KEY} $ZEBRA_POSTHOG_PLACEHOLDER" "$INFO_PLIST" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :${ZEBRA_POSTHOG_INFO_KEY} string $ZEBRA_POSTHOG_PLACEHOLDER" "$INFO_PLIST"
  echo "==> Zebra PostHog project token not set; telemetry disabled"
fi

echo "==> applying Zebra localization overlay"
python3 scripts/apply-zebra-localization-overlay.py \
  "$APP_PATH" \
  --overlay scripts/zebra-localization-overlay.json

if [[ "$SKIP_SIGN" -eq 0 ]]; then
  echo "==> signing helpers"
  if [[ -d "$APP_PATH/Contents/Resources/bin" ]]; then
    while IFS= read -r -d '' helper; do
      [[ -x "$helper" ]] || continue
      echo "    $(basename "$helper")"
      sign_path "$helper" "$HELPER_ENTITLEMENTS"
    done < <(find "$APP_PATH/Contents/Resources/bin" -type f -print0)
  fi

  echo "==> signing plugins"
  if [[ -d "$APP_PATH/Contents/PlugIns" ]]; then
    while IFS= read -r -d '' plugin; do
      /usr/bin/codesign \
        --force \
        --options runtime \
        --timestamp \
        --sign "$SIGNING_IDENTITY" \
        --deep \
        "$plugin"
    done < <(find "$APP_PATH/Contents/PlugIns" -mindepth 1 -maxdepth 1 -print0)
  fi

  echo "==> signing frameworks"
  if [[ -d "$APP_PATH/Contents/Frameworks" ]]; then
    while IFS= read -r -d '' framework; do
      /usr/bin/codesign \
        --force \
        --options runtime \
        --timestamp \
        --sign "$SIGNING_IDENTITY" \
        --deep \
        "$framework"
    done < <(find "$APP_PATH/Contents/Frameworks" -mindepth 1 -maxdepth 1 -print0)
  fi

  echo "==> signing app"
  sign_path "$APP_PATH" "$APP_ENTITLEMENTS"

  echo "==> verifying signature"
  /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"
else
  echo "==> skipped signing; local packaging test mode"
fi

mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"

if [[ "$SKIP_NOTARIZE" -eq 0 && -n "$NOTARY_PROFILE" ]]; then
  NOTARY_ZIP="${DIST_DIR}/Zebra-notary.zip"
  rm -f "$NOTARY_ZIP"

  echo "==> notarizing app"
  ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$NOTARY_ZIP"
  xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP_PATH"
  xcrun stapler validate "$APP_PATH"
  rm -f "$NOTARY_ZIP"
fi

echo "==> creating DMG"
create_zebra_dmg "$APP_PATH" "$DMG_PATH"

if [[ "$SKIP_SIGN" -eq 0 ]]; then
  echo "==> signing DMG"
  /usr/bin/codesign \
    --force \
    --timestamp \
    --sign "$SIGNING_IDENTITY" \
    "$DMG_PATH"
  /usr/bin/codesign --verify --strict --verbose=2 "$DMG_PATH"
fi

if [[ "$SKIP_NOTARIZE" -eq 0 && -n "$NOTARY_PROFILE" ]]; then
  echo "==> notarizing DMG"
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
else
  echo "==> skipped notarization; pass --notary-profile or set NOTARY_PROFILE"
fi

echo ""
echo "App: $APP_PATH"
echo "DMG: $DMG_PATH"
