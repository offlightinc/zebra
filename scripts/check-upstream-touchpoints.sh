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

# Collect changed files.
if [[ "$mode" == "staged" ]]; then
  mapfile -t changed < <(git -C "$ROOT" diff --cached --name-only --diff-filter=AMR)
else
  if ! git -C "$ROOT" rev-parse --verify --quiet "$base" >/dev/null; then
    echo "error: ref '$base' not found. Try fetching upstream first: git fetch upstream main" >&2
    exit 2
  fi
  mapfile -t changed < <(git -C "$ROOT" diff --name-only --diff-filter=AMR "$base"...HEAD)
fi

# Read allowlist into an associative array for O(1) lookup.
declare -A allowed=()
while IFS= read -r line; do
  trimmed="${line%%#*}"
  trimmed="${trimmed#"${trimmed%%[![:space:]]*}"}"
  trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
  [[ -z "$trimmed" ]] && continue
  allowed["$trimmed"]=1
done <"$ALLOWLIST"

# Resolve once: list every file that exists in upstream/main. Anything not in
# this set is a Zebra-only addition and isn't subject to the allowlist —
# Zebra files can move freely.
declare -A upstream_files=()
if git -C "$ROOT" rev-parse --verify --quiet upstream/main >/dev/null; then
  while IFS= read -r p; do
    upstream_files["$p"]=1
  done < <(git -C "$ROOT" ls-tree -r --name-only upstream/main)
else
  echo "warning: no 'upstream/main' ref — cannot distinguish Zebra-only files; falling back to path heuristics" >&2
fi

violations=()
for path in "${changed[@]}"; do
  [[ -z "$path" ]] && continue
  # Anything under Sources/Zebra/ or Packages/ZebraVault/ is Zebra's own area.
  case "$path" in
    Sources/Zebra/*|Packages/ZebraVault/*) continue ;;
  esac
  # Anything not under a cmux-relevant root is unrelated.
  case "$path" in
    Sources/*|Resources/*|cmuxTests/*|Packages/*|GhosttyTabs.xcodeproj/*) ;;
    *) continue ;;
  esac
  # If we have the upstream snapshot and this file doesn't exist there, it's
  # a Zebra-only addition — no allowlist required.
  if [[ ${#upstream_files[@]} -gt 0 && -z "${upstream_files[$path]+x}" ]]; then
    continue
  fi
  if [[ -z "${allowed[$path]+x}" ]]; then
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
