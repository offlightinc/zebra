#!/usr/bin/env bash
# disable-legacy-brainsync.sh
#
# One-shot helper for machines that have the external `local-offlight-brain-sync`
# launchd plist installed (from `~/brain-offlight/bin/install-local-offlight-brain-sync`).
# Zebra now ships built-in brain sync; running both in parallel is wasteful
# (they both target the same git repo and just serialize via git's own
# `.git/index.lock`, eating CPU and emitting redundant log spam).
#
# This script is deliberately decoupled from the zebra runtime — zebra never
# probes for or touches `~/Library/LaunchAgents/`. Users run this once after
# upgrading to a zebra build that includes built-in sync. New users who never
# installed the legacy plist don't need to run it.
#
# Phases:
#   1. `launchctl bootout` — remove the running launchd job for the user session
#   2. `launchctl disable` — record the label as disabled at the user level so
#      re-running `install-local-offlight-brain-sync` (which uses `bootstrap`)
#      doesn't reactivate it. This is the key step that prevents regression.
#   3. Move the plist file to `~/Library/Application Support/zebra/disabled-launchagents/`
#      so it's archived (not deleted) and can be restored with the companion
#      `revert-legacy-brainsync.sh` script.
#
# After running this, the only brain sync on the machine is zebra's built-in
# one. The brand-bound script (`~/brain-offlight/bin/local-offlight-brain-sync`)
# itself is left untouched on disk.

set -euo pipefail

readonly LABEL="ai.offlight.local-brain-sync"
readonly LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
readonly PLIST_PATH="$LAUNCH_AGENTS_DIR/$LABEL.plist"
readonly DISABLED_DIR="$HOME/Library/Application Support/zebra/disabled-launchagents"
readonly UID_VALUE="$(id -u)"
readonly DOMAIN="gui/$UID_VALUE"

log() {
  printf '[disable-legacy-brainsync] %s\n' "$*"
}

# Phase 1 — remove the running launchd job. `bootout` returns non-zero if the
# label isn't currently loaded; that's fine, we just want it gone.
if launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
  log "phase 1: launchctl bootout $DOMAIN/$LABEL"
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
else
  log "phase 1: $LABEL is not currently loaded (skipping bootout)"
fi

# Phase 2 — record disabled state at the user domain. This persists across
# reboots and across re-runs of `install-local-offlight-brain-sync`. The legacy
# install script calls `launchctl bootstrap`, which honors this disabled
# state — the job is registered but not started.
log "phase 2: launchctl disable $DOMAIN/$LABEL"
launchctl disable "$DOMAIN/$LABEL"

# Phase 3 — archive the plist file. Not deleted, so a user who needs to roll
# back can restore it with `revert-legacy-brainsync.sh`.
if [[ -f "$PLIST_PATH" ]]; then
  mkdir -p "$DISABLED_DIR"
  archive_target="$DISABLED_DIR/$LABEL.plist"
  # If a previous run already moved this plist, keep the latest by appending a
  # timestamp to avoid clobbering an existing archive.
  if [[ -e "$archive_target" ]]; then
    archive_target="$DISABLED_DIR/$LABEL.$(date +%Y%m%d-%H%M%S).plist"
  fi
  log "phase 3: mv $PLIST_PATH -> $archive_target"
  mv "$PLIST_PATH" "$archive_target"
else
  log "phase 3: no plist at $PLIST_PATH (already removed or never installed) — skipping mv"
fi

log "done."
log "to roll back: ./scripts/revert-legacy-brainsync.sh"
