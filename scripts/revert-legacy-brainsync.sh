#!/usr/bin/env bash
# revert-legacy-brainsync.sh
#
# Companion to `disable-legacy-brainsync.sh`. Restores the
# `ai.offlight.local-brain-sync` launchd plist that was archived by the disable
# script, clears the disabled-state record, and re-bootstraps the job so the
# external `local-offlight-brain-sync` runs again on the 15-minute cadence.
#
# Use only when explicitly reverting to the legacy external sync setup
# (e.g., debugging a regression in zebra's built-in sync). On a normal machine
# the built-in zebra sync is the source of truth and the legacy plist should
# stay disabled.
#
# Phases (reverse of disable-legacy-brainsync.sh):
#   1. Restore the archived plist back to `~/Library/LaunchAgents/`.
#   2. `launchctl enable` to clear the disabled state.
#   3. `launchctl bootstrap` to load + start the job for this user session.

set -euo pipefail

readonly LABEL="ai.offlight.local-brain-sync"
readonly LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
readonly PLIST_PATH="$LAUNCH_AGENTS_DIR/$LABEL.plist"
readonly DISABLED_DIR="$HOME/Library/Application Support/zebra/disabled-launchagents"
readonly DISABLED_PLIST="$DISABLED_DIR/$LABEL.plist"
readonly UID_VALUE="$(id -u)"
readonly DOMAIN="gui/$UID_VALUE"

log() {
  printf '[revert-legacy-brainsync] %s\n' "$*"
}

# Phase 1 — restore the plist. Prefer the canonical archive path
# ("$LABEL.plist"); if it doesn't exist, look for the most recent timestamped
# variant the disable script may have written.
if [[ -f "$DISABLED_PLIST" ]]; then
  source_plist="$DISABLED_PLIST"
elif compgen -G "$DISABLED_DIR/$LABEL.*.plist" > /dev/null; then
  source_plist="$(ls -1t "$DISABLED_DIR/$LABEL".*.plist 2>/dev/null | head -1)"
else
  log "no archived plist in $DISABLED_DIR — cannot revert."
  log "run \`~/brain-offlight/bin/install-local-offlight-brain-sync\` to recreate from scratch."
  exit 1
fi

mkdir -p "$LAUNCH_AGENTS_DIR"
log "phase 1: mv $source_plist -> $PLIST_PATH"
mv "$source_plist" "$PLIST_PATH"

# Phase 2 — clear the user-domain disabled flag set by the disable script.
log "phase 2: launchctl enable $DOMAIN/$LABEL"
launchctl enable "$DOMAIN/$LABEL"

# Phase 3 — load + start.
log "phase 3: launchctl bootstrap $DOMAIN $PLIST_PATH"
launchctl bootstrap "$DOMAIN" "$PLIST_PATH"

log "done. legacy sync is active again on the 15-minute cadence."
log "to disable again: ./scripts/disable-legacy-brainsync.sh"
