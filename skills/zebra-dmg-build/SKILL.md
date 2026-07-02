---
name: zebra-dmg-build
description: Build Zebra macOS release-test artifacts from the offlightinc/zebra checkout. Use when Codex needs to create a copyable Zebra.app or dist/Zebra.dmg for testing on another Mac without transferring local user settings; handle Developer ID, notarization, ad-hoc signing, create-dmg, and verification for Zebra release overlay builds.
---

# Zebra DMG Build

## Purpose

Create a portable Zebra macOS app artifact from a Zebra checkout using the repository's Zebra release overlay. The deliverable is normally `dist/Zebra.dmg`, plus `build-zebra-release/Build/Products/Release/Zebra.app`.

This builds the existing Xcode `cmux` scheme as an intermediate, then copies and patches it into `Zebra.app`. Do not pass `PRODUCT_NAME=Zebra` to `xcodebuild`; that can rename Swift package resource bundles and break the build.

## Build Decision

- For quick testing on another Mac: build a signed but not notarized DMG.
- For external/team distribution with normal Gatekeeper behavior: build with a Developer ID identity and notary profile.
- If no valid codesigning identity exists on the machine: use ad-hoc signing for local testing only.
- Do not use `scripts/reload.sh --tag` for this task; it creates `cmux DEV <tag>.app`, not the branded Zebra release artifact.

## Commands

Run from the Zebra checkout root.

Preferred local test build when Developer ID exists:

```bash
./scripts/build-zebra-notarized-dmg.sh --skip-notarize
```

Notarized build when a notary profile is configured:

```bash
./scripts/build-zebra-notarized-dmg.sh --notary-profile <profile-name>
```

Ad-hoc fallback when `security find-identity -v -p codesigning` reports no valid identities, or signing fails with `no identity found`:

```bash
APPLE_SIGNING_IDENTITY=- ./scripts/build-zebra-notarized-dmg.sh --skip-notarize
```

If the build already succeeded and only the signing/DMG step failed, reuse the existing app:

```bash
APPLE_SIGNING_IDENTITY=- ./scripts/build-zebra-notarized-dmg.sh --skip-build --skip-notarize
```

If `create-dmg` is missing:

```bash
brew install create-dmg
```

## Expected Output

The script should finish with lines like:

```text
App: build-zebra-release/Build/Products/Release/Zebra.app
DMG: dist/Zebra.dmg
```

The DMG is the artifact to transfer to another Mac. It does not include the current user's settings, vaults, secrets, login sessions, `~/.codex`, `~/.gbrain`, `~/Library/Application Support/zebra`, or git worktrees.

## Verification

After building, verify:

```bash
ls -lh dist/Zebra.dmg
/usr/libexec/PlistBuddy \
  -c 'Print :CFBundleName' \
  -c 'Print :CFBundleDisplayName' \
  -c 'Print :CFBundleIdentifier' \
  build-zebra-release/Build/Products/Release/Zebra.app/Contents/Info.plist
codesign --verify --deep --strict --verbose=2 build-zebra-release/Build/Products/Release/Zebra.app
codesign --verify --strict --verbose=2 dist/Zebra.dmg
shasum -a 256 dist/Zebra.dmg
```

Expected plist values:

```text
Zebra
Zebra
com.offlight.zebra
```

## Sharing

This repository includes `skills.sh`, which can install this skill into the local Codex skills directory:

```bash
./skills.sh --skill zebra-dmg-build
```

By default, `skills.sh` installs into `${CODEX_HOME:-$HOME/.codex}/skills`. Use `--dest` to install somewhere else.

## Caveats

- Ad-hoc signed or non-notarized DMGs may be blocked by Gatekeeper on another Mac. For testing, use right-click/Open; for natural external installs, use Developer ID plus notarization.
- A warning like `cargo not found; skipping optional libcmux_command_palette_nucleo_ffi.dylib build` does not necessarily fail the app build, but report it because the optional command-palette FFI dylib is absent.
- Existing Swift/macOS deprecation warnings are common and do not by themselves mean packaging failed.
- If the user wants a clickable app path, link the DMG or app path with an absolute local markdown file link in the final answer.
