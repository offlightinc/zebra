#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT_DIR/Resources/zebra-agent-onboarding"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/zebra-agent-onboarding-resume.XXXXXX")"

trap 'rm -rf "$TMP_ROOT"' EXIT

CASE_DIR=""
HOME_DIR=""
APP_DIR=""
WORK_DIR=""
FAKE_LOG=""
STATE_FILE=""
RUN_OUTPUT=""
RUN_STATUS=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  if [[ -n "${RUN_OUTPUT:-}" ]]; then
    printf '%s\n' "$RUN_OUTPUT" >&2
  fi
  exit 1
}

assert_eq() {
  local actual="$1"
  local expected="$2"
  local label="$3"
  [[ "$actual" == "$expected" ]] || fail "$label: expected <$expected>, got <$actual>"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  [[ "$haystack" == *"$needle"* ]] || fail "$label: missing <$needle>"
}

plist_raw() {
  plutil -extract "$2" raw -o - "$1"
}

setup_case() {
  local name="$1"
  CASE_DIR="$TMP_ROOT/$name"
  HOME_DIR="$CASE_DIR/home"
  APP_DIR="$CASE_DIR/app-support"
  WORK_DIR="$CASE_DIR/work"
  FAKE_LOG="$CASE_DIR/fake-agent.log"
  STATE_FILE="$APP_DIR/onboarding/agent-cli-state.json"
  mkdir -p "$HOME_DIR/.local/bin" "$APP_DIR/onboarding" "$APP_DIR/agent" "$WORK_DIR"
  : > "$FAKE_LOG"
}

add_fake_agent() {
  local agent="$1"
  local binary
  case "$agent" in
    claude) binary=claude ;;
    codex) binary=codex ;;
    antigravity) binary=agy ;;
    *) fail "unknown fake agent: $agent" ;;
  esac
  cat > "$HOME_DIR/.local/bin/$binary" <<FAKE
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" == "--version" ]]; then
  printf '$binary fake 1.0\n'
  exit 0
fi
printf '$agent:%s\n' "\$*" >> "\${ZEBRA_FAKE_AGENT_LOG:?}"
exit 0
FAKE
  chmod +x "$HOME_DIR/.local/bin/$binary"
}

write_preferences() {
  local primary_agent="$1"
  cat > "$APP_DIR/agent/preferences.json" <<JSON
{
  "schemaVersion": 1,
  "primaryAgent": "$primary_agent",
  "surfaceOverrides": {}
}
JSON
}

write_state() {
  local phase="$1"
  local run_id="$2"
  local selected_agent="${3:-}"
  local selected_json="null"
  if [[ -n "$selected_agent" ]]; then
    selected_json="\"$selected_agent\""
  fi
  cat > "$STATE_FILE" <<JSON
{
  "schemaVersion": 1,
  "runId": "$run_id",
  "phase": "$phase",
  "updatedAt": "2026-05-29T00:00:00Z",
  "savedPrimary": null,
  "selectedAgent": $selected_json,
  "candidates": [],
  "error": null
}
JSON
}

run_onboarding() {
  local input="$1"
  local output_file="$CASE_DIR/output.txt"
  set +e
  HOME="$HOME_DIR" \
    ZEBRA_APP_SUPPORT_DIR="$APP_DIR" \
    ZEBRA_AGENT_ONBOARDING_INCLUDE_GLOBAL_PATHS=0 \
    ZEBRA_FAKE_AGENT_LOG="$FAKE_LOG" \
    PATH="/usr/bin:/bin" \
    "$SCRIPT" run --cwd "$WORK_DIR" >"$output_file" 2>&1 <<<"$input"
  RUN_STATUS=$?
  set -e
  RUN_OUTPUT="$(cat "$output_file")"
}

test_waiting_for_continue_resumes_menu() {
  setup_case waiting
  write_preferences antigravity
  write_state waiting_for_continue run-waiting antigravity

  run_onboarding $'4\n'

  assert_eq "$RUN_STATUS" "1" "exit-for-now status"
  assert_contains "$RUN_OUTPUT" "Resuming Zebra agent onboarding for Antigravity." "resume message"
  assert_contains "$RUN_OUTPUT" "Antigravity exited before reporting ready." "continue menu"
  assert_eq "$(plist_raw "$STATE_FILE" runId)" "run-waiting" "run id is preserved"
  assert_eq "$(plist_raw "$STATE_FILE" phase)" "waiting_for_continue" "phase remains waiting"
  assert_eq "$(cat "$FAKE_LOG")" "" "agent is not relaunched automatically"
}

test_agent_working_resumes_to_continue_menu() {
  setup_case working
  write_preferences antigravity
  write_state agent_working run-working antigravity

  run_onboarding $'4\n'

  assert_eq "$RUN_STATUS" "1" "exit-for-now status"
  assert_contains "$RUN_OUTPUT" "Resuming Zebra agent onboarding for Antigravity." "resume message"
  assert_contains "$RUN_OUTPUT" "Antigravity exited before reporting ready." "continue menu"
  assert_eq "$(plist_raw "$STATE_FILE" runId)" "run-working" "run id is preserved"
  assert_eq "$(plist_raw "$STATE_FILE" phase)" "waiting_for_continue" "working phase moves to waiting"
  assert_eq "$(cat "$FAKE_LOG")" "" "agent is not relaunched automatically"
}

test_choose_install_target_resumes_install_menu() {
  setup_case install-target
  write_state choose_install_target run-install

  run_onboarding $'3\nn\n4\n'

  assert_eq "$RUN_STATUS" "1" "declined install exit status"
  assert_contains "$RUN_OUTPUT" "Resuming Zebra agent onboarding at install selection." "resume message"
  assert_contains "$RUN_OUTPUT" "Zebra will run the official installer for Antigravity:" "install prompt"
  assert_eq "$(plist_raw "$STATE_FILE" runId)" "run-install" "run id is preserved"
  assert_eq "$(plist_raw "$STATE_FILE" phase)" "choose_install_target" "phase remains install selection"
}

test_fresh_choice_lists_missing_agents() {
  setup_case fresh-missing
  add_fake_agent codex

  run_onboarding $'3\nn\n4\n'

  assert_eq "$RUN_STATUS" "1" "declined missing-agent install status"
  assert_contains "$RUN_OUTPUT" "Which agent should Zebra use by default?" "primary prompt"
  assert_contains "$RUN_OUTPUT" "2. Codex [installed]" "installed option"
  assert_contains "$RUN_OUTPUT" "3. Antigravity [not installed]" "missing option"
  assert_contains "$RUN_OUTPUT" "Zebra will run the official installer for Antigravity:" "missing selection installs"
  assert_eq "$(plist_raw "$STATE_FILE" phase)" "choose_primary" "declined install returns to primary choice state"
  assert_eq "$(cat "$FAKE_LOG")" "" "installed agent is not launched when missing agent is selected"
}

test_fresh_choice_launches_installed_selection() {
  setup_case fresh-installed
  add_fake_agent codex

  run_onboarding $'2\n4\n'

  assert_eq "$RUN_STATUS" "1" "exit-for-now status"
  assert_contains "$RUN_OUTPUT" "2. Codex [installed]" "installed option"
  assert_contains "$RUN_OUTPUT" "Starting Codex for Zebra onboarding." "selected installed agent launches"
  assert_contains "$(cat "$FAKE_LOG")" "codex:" "fake codex launched"
  assert_eq "$(plist_raw "$APP_DIR/agent/preferences.json" primaryAgent)" "codex" "primary preference is saved"
  assert_eq "$(plist_raw "$STATE_FILE" selectedAgent)" "codex" "selected agent is persisted"
  assert_eq "$(plist_raw "$STATE_FILE" phase)" "waiting_for_continue" "launch exit moves to continue menu"
}

test_complete_state_exits_without_scan() {
  setup_case complete
  write_preferences antigravity
  write_state complete run-complete antigravity

  run_onboarding ''

  assert_eq "$RUN_STATUS" "0" "complete status"
  assert_contains "$RUN_OUTPUT" "Zebra agent onboarding is already complete." "complete message"
  assert_eq "$(cat "$FAKE_LOG")" "" "agent is not scanned or launched"
}

test_waiting_for_continue_resumes_menu
test_agent_working_resumes_to_continue_menu
test_choose_install_target_resumes_install_menu
test_fresh_choice_lists_missing_agents
test_fresh_choice_launches_installed_selection
test_complete_state_exits_without_scan

printf 'PASS: zebra agent onboarding resume\n'
