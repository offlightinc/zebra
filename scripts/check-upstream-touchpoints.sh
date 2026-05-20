#!/usr/bin/env bash
# Verify that no cmux file outside the approved allowlist is being modified.
#
# Default: diffs HEAD against `upstream/main` and inspects every changed path.
# Override the base ref with `--base <ref>` (e.g., `--base origin/main`) or
# `--staged` to scan staged changes only (for use as a pre-commit hook).
#
# Usage:
#   scripts/check-upstream-touchpoints.sh              # vs upstream/main
#   scripts/check-upstream-touchpoints.sh --staged     # staged-only
#   scripts/check-upstream-touchpoints.sh --base HEAD~1
#
# Exit codes:
#   0  no unapproved cmux file changes
#   1  found at least one unapproved cmux file change
#   2  invalid arguments / setup error
#
# bash 3.2 compatible (macOS default `/bin/bash`) — no `mapfile`, no
# `declare -A`. Linear scans are fine: the allowlist + upstream file set are
# both small enough that O(n*m) lookups never show up in profile.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ALLOWLIST="$ROOT/docs/upstream-touchpoints.txt"

if [[ ! -f "$ALLOWLIST" ]]; then
  echo "error: allowlist missing at $ALLOWLIST" >&2
  exit 2
fi

mode="diff"
base="upstream/main"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --staged) mode="staged"; shift ;;
    --base) base="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "error: unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

# Collect changed files (bash 3.2: no `mapfile`).
changed=()
if [[ "$mode" == "staged" ]]; then
  while IFS= read -r line; do
    changed+=("$line")
  done < <(git -C "$ROOT" diff --cached --name-only --diff-filter=AMR)
else
  if ! git -C "$ROOT" rev-parse --verify --quiet "$base" >/dev/null; then
    echo "error: ref '$base' not found. Try fetching upstream first: git fetch upstream main" >&2
    exit 2
  fi
  while IFS= read -r line; do
    changed+=("$line")
  done < <(git -C "$ROOT" diff --name-only --diff-filter=AMR "$base"...HEAD)
fi

# Read allowlist into a plain array (bash 3.2: no associative arrays).
allowed=()
while IFS= read -r line; do
  trimmed="${line%%#*}"
  trimmed="${trimmed#"${trimmed%%[![:space:]]*}"}"
  trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
  [[ -z "$trimmed" ]] && continue
  allowed+=("$trimmed")
done <"$ALLOWLIST"

# Resolve once: list every file that exists in upstream/main. Anything not in
# this set is a Zebra-only addition and isn't subject to the allowlist.
upstream_files=()
have_upstream=0
if git -C "$ROOT" rev-parse --verify --quiet upstream/main >/dev/null; then
  have_upstream=1
  while IFS= read -r p; do
    upstream_files+=("$p")
  done < <(git -C "$ROOT" ls-tree -r --name-only upstream/main)
else
  echo "warning: no 'upstream/main' ref — cannot distinguish Zebra-only files; falling back to path heuristics" >&2
fi

# Linear membership helpers. Allowlist size stays in the dozens; upstream
# file set is a few thousand at most. Even with O(n) lookups the whole hook
# finishes in well under 100ms, which is the budget that matters.
contains_path() {
  local needle="$1"; shift
  local item
  for item in "$@"; do
    if [[ "$item" == "$needle" ]]; then
      return 0
    fi
  done
  return 1
}

violations=()
for path in "${changed[@]}"; do
  [[ -z "$path" ]] && continue
  # Anything under Sources/Zebra/ or Packages/ZebraVault/ is Zebra's own area.
  case "$path" in
    Sources/Zebra/*|Packages/ZebraVault/*) continue ;;
  esac
  # Anything not under a cmux-relevant root is unrelated.
  case "$path" in
    Sources/*|Resources/*|cmuxTests/*|Packages/*|cmux.xcodeproj/*) ;;
    *) continue ;;
  esac
  # If we have the upstream snapshot and this file doesn't exist there, it's
  # a Zebra-only addition — no allowlist required.
  if [[ $have_upstream -eq 1 ]] && ! contains_path "$path" "${upstream_files[@]}"; then
    continue
  fi
  if ! contains_path "$path" "${allowed[@]}"; then
    violations+=("$path")
  fi
done

if [[ ${#violations[@]} -gt 0 ]]; then
  echo "Upstream touchpoint guard: the following cmux files are modified but not in docs/upstream-touchpoints.txt:" >&2
  for v in "${violations[@]}"; do
    echo "  - $v" >&2
  done
  echo "" >&2
  echo "If this change truly needs a new cmux seam, add the path to docs/upstream-touchpoints.txt and document the seam in docs/upstream-touchpoints.md." >&2
  exit 1
fi

echo "Upstream touchpoint guard: ok (${#changed[@]} file(s) checked against allowlist)"
