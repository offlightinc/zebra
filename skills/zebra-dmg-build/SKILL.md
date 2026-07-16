---
name: zebra-dmg-build
description: Build Zebra macOS release-test artifacts from the offlightinc/zebra checkout. Use when Codex needs to create a copyable local-test Zebra.app or dist/Zebra.dmg for testing on another Mac without transferring local user settings; handle Developer ID, notarization, ad-hoc signing, create-dmg, PostHog token injection, and verification for Zebra release overlay builds.
---

# Zebra DMG Build

## Purpose

Create a portable local-test Zebra macOS app artifact from a Zebra checkout using the repository's Zebra release overlay. The deliverable is normally `dist/Zebra.dmg`, plus `build-zebra-release/Build/Products/Release/Zebra.app`.

This skill is for release-style local verification and handoff builds. It does
not replace the official GitHub Actions release workflow for signed,
notarized, externally distributed builds.

This builds the existing Xcode `cmux` scheme as an intermediate, then copies and patches it into `Zebra.app`. Do not pass `PRODUCT_NAME=Zebra` to `xcodebuild`; that can rename Swift package resource bundles and break the build.

## Build Decision

- For quick testing on another Mac: build a signed but not notarized DMG.
- For external/team distribution with normal Gatekeeper behavior: build with a Developer ID identity and notary profile.
- If no valid codesigning identity exists on the machine: use ad-hoc signing for local testing only.
- Do not use `scripts/reload.sh --tag` for this task; it creates `cmux DEV <tag>.app`, not the branded Zebra release artifact.

## Commands

Run from the Zebra checkout root.

The build script performs preflight checks before starting the expensive
universal Release build. If preflight reports a missing dependency, install it
and rerun the same command:

```bash
brew install zig@0.15
xcodebuild -downloadComponent MetalToolchain
brew install create-dmg
```

Do not substitute a different Zig version. The Ghostty CLI helper requires Zig
0.15.2, and the build prefers Homebrew `zig@0.15` for Xcode 26 compatibility.

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

The script preserves `build-zebra-release` by default so a retry can reuse
Xcode build caches. Use `--clean-build` only when a clean rebuild is explicitly
needed:

```bash
APPLE_SIGNING_IDENTITY=- \
./scripts/build-zebra-notarized-dmg.sh --clean-build --skip-notarize
```

PostHog-enabled local telemetry smoke build:

```bash
ZEBRA_POSTHOG_API_KEY="$ZEBRA_POSTHOG_API_KEY" \
APPLE_SIGNING_IDENTITY=- \
./scripts/build-zebra-notarized-dmg.sh --require-posthog-key --skip-notarize
```

Use this only for local smoke testing that a release-style Zebra build can send
events to PostHog without requiring Apple Developer notarization. The build is
ad-hoc signed, may need right-click/Open on first launch, and is not a
substitute for the official signed/notarized release artifact. PostHog event
sending itself does not require Developer ID signing.

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
lipo -archs build-zebra-release/Build/Products/Release/Zebra.app/Contents/MacOS/cmux
codesign --verify --deep --strict --verbose=2 build-zebra-release/Build/Products/Release/Zebra.app
codesign --verify --strict --verbose=2 dist/Zebra.dmg
shasum -a 256 dist/Zebra.dmg
```

Expected plist values:

```text
Zebra
Zebra
com.offlight.zebra
x86_64 arm64
```

For PostHog builds only, verify `ZebraPostHogProjectToken` separately and ensure
it is present, begins with `phc_`, and is not
`REPLACE_WITH_ZEBRA_POSTHOG_PROJECT_TOKEN`. Do not print full secrets in CI logs
unless the value is already intentionally public. For ordinary builds, the
placeholder is expected and telemetry is disabled.

## PostHog Event Smoke Test

Use this flow when the goal is to prove local release-style smoke builds can
send Zebra telemetry events:

1. Build with `ZEBRA_POSTHOG_API_KEY` and `--require-posthog-key`.
2. Confirm `ZebraPostHogProjectToken` exists in
   `build-zebra-release/Build/Products/Release/Zebra.app/Contents/Info.plist`.
3. Ensure telemetry is enabled for the Zebra bundle and clear daily/hourly
   suppression keys so app activation emits fresh events:

```bash
defaults write com.offlight.zebra sendAnonymousTelemetry -bool true
defaults delete com.offlight.zebra zebra.posthog.lastActiveDayUTC 2>/dev/null || true
defaults delete com.offlight.zebra zebra.posthog.lastActiveHourUTC 2>/dev/null || true
```

4. Launch `build-zebra-release/Build/Products/Release/Zebra.app`. In Codex,
   launching GUI apps requires escalated approval.
5. Generate at least one user action after launch. App activation should emit
   `zebra_app_active_daily` / `zebra_app_active_hourly`; submitting ChatPill
   prompt text should emit `zebra_chatpill_prompt_submitted`.
6. Verify in PostHog project 505579 with:

```sql
SELECT event, count(), uniq(distinct_id), min(timestamp), max(timestamp)
FROM events
WHERE timestamp > now() - interval 1 day
  AND event LIKE 'zebra_%'
GROUP BY event
ORDER BY count() DESC
```

Expected: `zebra_%` events appear, `path_hash` / `item_id_hash` values are
64-character lowercase hex when present, and raw path, prompt, query, or document
text is absent.

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
- If a build fails after compilation starts, fix the reported dependency and rerun without `--clean-build`; the default incremental build reuses DerivedData.
- If the user wants a clickable app path, link the DMG or app path with an absolute local markdown file link in the final answer.
