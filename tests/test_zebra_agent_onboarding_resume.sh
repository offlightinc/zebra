#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT_DIR/Resources/zebra-agent-onboarding"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/zebra-agent-onboarding-resume.XXXXXX")"

cleanup() {
  if [[ -n "${RUN_PID:-}" ]]; then
    kill "$RUN_PID" 2>/dev/null || true
  fi
  if [[ -n "${FAKE_HOLD_FILE:-}" && -f "$FAKE_HOLD_FILE" ]]; then
    kill "$(cat "$FAKE_HOLD_FILE")" 2>/dev/null || true
  fi
  rm -rf "$TMP_ROOT"
}

trap cleanup EXIT

CASE_DIR=""
HOME_DIR=""
APP_DIR=""
WORK_DIR=""
FAKE_LOG=""
STATE_FILE=""
RUN_OUTPUT=""
RUN_STATUS=0
READY_AGENTS=""
FAKE_HOLD_FILE=""
FAKE_RELEASE_FILE=""
RUN_PID=""
RUN_OUTPUT_FILE=""

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
  READY_AGENTS=""
  FAKE_HOLD_FILE=""
  FAKE_RELEASE_FILE=""
  RUN_PID=""
  RUN_OUTPUT_FILE=""
  mkdir -p "$HOME_DIR/.local/bin" "$APP_DIR/onboarding" "$APP_DIR/agent" "$WORK_DIR"
  printf 'export PATH="$HOME/.local/bin:$PATH"\n' > "$HOME_DIR/.bash_profile"
  : > "$FAKE_LOG"
}

fake_agent_binary_name() {
  local agent="$1"
  case "$agent" in
    claude) printf 'claude' ;;
    codex) printf 'codex' ;;
    antigravity) printf 'agy' ;;
    *) fail "unknown fake agent: $agent" ;;
  esac
}

write_fake_agent() {
  local agent="$1"
  local target="$2"
  local binary
  binary="$(fake_agent_binary_name "$agent")"
  cat > "$target" <<FAKE
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" == "--version" ]]; then
  printf '$binary fake 1.0\n'
  exit 0
fi
agent_name='$agent'
agent_ready() {
  case ",\${ZEBRA_FAKE_READY_AGENTS:-}," in
    *,"\$agent_name",*) return 0 ;;
    *) return 1 ;;
  esac
}
if [[ "\$agent_name" == "claude" && "\${1:-}" == "auth" && "\${2:-}" == "status" ]]; then
  printf '$agent:%s\n' "\$*" >> "\${ZEBRA_FAKE_AGENT_LOG:?}"
  if agent_ready; then
    printf '{"loggedIn":true}\n'
    exit 0
  fi
  printf '{"loggedIn":false}\n'
  exit 1
fi
if [[ "\$agent_name" == "codex" && "\${1:-}" == "login" && "\${2:-}" == "status" ]]; then
  printf '$agent:%s\n' "\$*" >> "\${ZEBRA_FAKE_AGENT_LOG:?}"
  if agent_ready; then
    printf 'Logged in using ChatGPT\n'
    exit 0
  fi
  printf 'Not logged in\n' >&2
  exit 1
fi
if [[ "\$#" -eq 0 && -n "\${ZEBRA_FAKE_HOLD_FILE:-}" && -n "\${ZEBRA_FAKE_RELEASE_FILE:-}" ]]; then
  printf '$agent:%s\n' "\$*" >> "\${ZEBRA_FAKE_AGENT_LOG:?}"
  printf '%s\n' "\$\$" > "\$ZEBRA_FAKE_HOLD_FILE"
  while [[ ! -f "\$ZEBRA_FAKE_RELEASE_FILE" ]]; do
    sleep 0.1
  done
  exit 0
fi
printf '$agent:%s\n' "\$*" >> "\${ZEBRA_FAKE_AGENT_LOG:?}"
exit 0
FAKE
  chmod +x "$target"
}

add_fake_agent() {
  local agent="$1"
  local binary
  binary="$(fake_agent_binary_name "$agent")"
  write_fake_agent "$agent" "$HOME_DIR/.local/bin/$binary"
}

add_fake_installer_for_agent() {
  local agent="$1"
  local binary source
  binary="$(fake_agent_binary_name "$agent")"
  mkdir -p "$CASE_DIR/install-source"
  source="$CASE_DIR/install-source/$binary"
  write_fake_agent "$agent" "$source"
  cat > "$HOME_DIR/.local/bin/curl" <<FAKE
#!/usr/bin/env bash
set -euo pipefail
cat <<'INSTALL'
#!/usr/bin/env sh
set -eu
mkdir -p "\$HOME/.local/bin"
cp "$source" "\$HOME/.local/bin/$binary"
chmod +x "\$HOME/.local/bin/$binary"
INSTALL
FAKE
  chmod +x "$HOME_DIR/.local/bin/curl"
}

set_ready_agents() {
  READY_AGENTS="$1"
}

hold_fake_agent() {
  FAKE_HOLD_FILE="$CASE_DIR/fake-agent.pid"
  FAKE_RELEASE_FILE="$CASE_DIR/release-fake-agent"
  rm -f "$FAKE_HOLD_FILE" "$FAKE_RELEASE_FILE"
}

write_antigravity_ready_state() {
  mkdir -p "$HOME_DIR/.gemini/antigravity-cli/log"
  printf '{"access_token":"fake","refresh_token":"fake"}\n' > "$HOME_DIR/.gemini/oauth_creds.json"
  printf 'I0601 00:00:00 server_oauth.go:217] OAuth: authenticated successfully as user@example.com\n' >> "$HOME_DIR/.gemini/antigravity-cli/log/cli-ready.log"
}

wait_for_fake_agent_hold() {
  local i
  for i in {1..30}; do
    [[ -f "$FAKE_HOLD_FILE" ]] && return 0
    sleep 0.2
  done
  fail "interactive fake agent did not start"
}

wait_for_primary_agent() {
  local expected="$1"
  local primary i
  for i in {1..30}; do
    primary="$(plist_raw "$APP_DIR/agent/preferences.json" primaryAgent 2>/dev/null || true)"
    [[ "$primary" == "$expected" ]] && return 0
    sleep 0.2
  done
  fail "primary preference was not saved as $expected"
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
    ZEBRA_AGENT_READINESS_POLL_INTERVAL_SECONDS=1 \
    ZEBRA_AGENT_ANTIGRAVITY_AUTH_CHECK_BACKOFF_SECONDS=1 \
    ZEBRA_FAKE_AGENT_LOG="$FAKE_LOG" \
    ZEBRA_FAKE_READY_AGENTS="$READY_AGENTS" \
    ZEBRA_FAKE_HOLD_FILE="$FAKE_HOLD_FILE" \
    ZEBRA_FAKE_RELEASE_FILE="$FAKE_RELEASE_FILE" \
    PATH="/usr/bin:/bin" \
    "$SCRIPT" run --cwd "$WORK_DIR" >"$output_file" 2>&1 <<<"$input"
  RUN_STATUS=$?
  set -e
  RUN_OUTPUT="$(cat "$output_file")"
}

run_onboarding_async() {
  local input="$1"
  RUN_OUTPUT_FILE="$CASE_DIR/output-async.txt"
  HOME="$HOME_DIR" \
    ZEBRA_APP_SUPPORT_DIR="$APP_DIR" \
    ZEBRA_AGENT_ONBOARDING_INCLUDE_GLOBAL_PATHS=0 \
    ZEBRA_AGENT_READINESS_POLL_INTERVAL_SECONDS=1 \
    ZEBRA_AGENT_ANTIGRAVITY_AUTH_CHECK_BACKOFF_SECONDS=1 \
    ZEBRA_FAKE_AGENT_LOG="$FAKE_LOG" \
    ZEBRA_FAKE_READY_AGENTS="$READY_AGENTS" \
    ZEBRA_FAKE_HOLD_FILE="$FAKE_HOLD_FILE" \
    ZEBRA_FAKE_RELEASE_FILE="$FAKE_RELEASE_FILE" \
    PATH="/usr/bin:/bin" \
    "$SCRIPT" run --cwd "$WORK_DIR" >"$RUN_OUTPUT_FILE" 2>&1 <<<"$input" &
  RUN_PID="$!"
}

finish_onboarding_async() {
  set +e
  wait "$RUN_PID"
  RUN_STATUS=$?
  set -e
  RUN_OUTPUT="$(cat "$RUN_OUTPUT_FILE")"
  RUN_PID=""
}

run_mark_ready() {
  local agent="$1"
  local run_id="$2"
  local output_file="$CASE_DIR/mark-ready-output.txt"
  set +e
  HOME="$HOME_DIR" \
    ZEBRA_APP_SUPPORT_DIR="$APP_DIR" \
    ZEBRA_AGENT_ONBOARDING_INCLUDE_GLOBAL_PATHS=0 \
    PATH="/usr/bin:/bin" \
    "$SCRIPT" mark-ready --agent "$agent" --run-id "$run_id" >"$output_file" 2>&1
  RUN_STATUS=$?
  set -e
  RUN_OUTPUT="$(cat "$output_file")"
}

test_waiting_for_continue_resumes_menu() {
  setup_case waiting
  write_preferences antigravity
  write_state waiting_for_continue run-waiting antigravity

  run_onboarding $'2\n'

  assert_eq "$RUN_STATUS" "1" "exit-for-now status"
  assert_contains "$RUN_OUTPUT" "Resuming Zebra agent onboarding for Antigravity." "resume message"
  assert_contains "$RUN_OUTPUT" "Antigravity did not finish Zebra setup." "continue menu"
  assert_eq "$(plist_raw "$STATE_FILE" runId)" "run-waiting" "run id is preserved"
  assert_eq "$(plist_raw "$STATE_FILE" phase)" "waiting_for_continue" "phase remains waiting"
  assert_eq "$(cat "$FAKE_LOG")" "" "agent is not relaunched automatically"
}

test_agent_working_resumes_to_continue_menu() {
  setup_case working
  write_preferences antigravity
  write_state agent_working run-working antigravity

  run_onboarding $'2\n'

  assert_eq "$RUN_STATUS" "1" "exit-for-now status"
  assert_contains "$RUN_OUTPUT" "Resuming Zebra agent onboarding for Antigravity." "resume message"
  assert_contains "$RUN_OUTPUT" "Antigravity did not finish Zebra setup." "continue menu"
  assert_eq "$(plist_raw "$STATE_FILE" runId)" "run-working" "run id is preserved"
  assert_eq "$(plist_raw "$STATE_FILE" phase)" "waiting_for_continue" "working phase moves to waiting"
  assert_eq "$(cat "$FAKE_LOG")" "" "agent is not relaunched automatically"
}

test_choose_install_target_resumes_install_menu() {
  setup_case install-target
  write_state choose_install_target run-install

  run_onboarding $'3\nn\n3\n'

  assert_eq "$RUN_STATUS" "1" "declined install exit status"
  assert_contains "$RUN_OUTPUT" "Resuming Zebra agent onboarding at install selection." "resume message"
  assert_contains "$RUN_OUTPUT" "Zebra will run the official installer for Antigravity:" "install prompt"
  assert_eq "$(plist_raw "$STATE_FILE" runId)" "run-install" "run id is preserved"
  assert_eq "$(plist_raw "$STATE_FILE" phase)" "choose_install_target" "phase remains install selection"
}

test_fresh_choice_lists_missing_agents() {
  setup_case fresh-missing
  add_fake_agent codex

  run_onboarding $'3\nn\n3\n'

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

  run_onboarding $'2\n2\n'

  assert_eq "$RUN_STATUS" "1" "exit-for-now status"
  assert_contains "$RUN_OUTPUT" "2. Codex [installed]" "installed option"
  assert_contains "$RUN_OUTPUT" "Starting Codex for Zebra onboarding." "selected installed agent launches"
  assert_contains "$(cat "$FAKE_LOG")" "codex:" "fake codex launched"
  assert_contains "$(cat "$FAKE_LOG")" "codex:login status" "codex readiness uses login status"
  [[ ! -f "$APP_DIR/agent/preferences.json" ]] || fail "primary preference should not be saved before mark-ready"
  assert_eq "$(plist_raw "$STATE_FILE" selectedAgent)" "codex" "selected agent is persisted"
  assert_eq "$(plist_raw "$STATE_FILE" phase)" "waiting_for_continue" "launch exit moves to continue menu"
}

test_claude_status_probe_completes_onboarding() {
  setup_case claude-ready
  add_fake_agent claude
  set_ready_agents claude

  run_onboarding $'1\n'

  assert_eq "$RUN_STATUS" "0" "ready claude status"
  assert_contains "$RUN_OUTPUT" "Zebra verified Claude Code readiness. Onboarding is complete." "ready message"
  assert_contains "$(cat "$FAKE_LOG")" "claude:auth status --json" "claude readiness uses auth status"
  assert_eq "$(plist_raw "$STATE_FILE" phase)" "complete" "state phase is complete"
  assert_eq "$(plist_raw "$APP_DIR/agent/preferences.json" primaryAgent)" "claude" "primary preference is saved after readiness"
}

test_codex_status_probe_completes_onboarding() {
  setup_case codex-ready
  add_fake_agent codex
  set_ready_agents codex

  run_onboarding $'2\n'

  assert_eq "$RUN_STATUS" "0" "ready codex status"
  assert_contains "$RUN_OUTPUT" "Zebra verified Codex readiness. Onboarding is complete." "ready message"
  assert_contains "$(cat "$FAKE_LOG")" "codex:login status" "codex readiness uses login status"
  assert_eq "$(plist_raw "$STATE_FILE" phase)" "complete" "state phase is complete"
  assert_eq "$(plist_raw "$APP_DIR/agent/preferences.json" primaryAgent)" "codex" "primary preference is saved after readiness"
}

test_codex_polling_completes_while_cli_is_still_running() {
  local primary pid i
  setup_case codex-polling
  add_fake_agent codex
  set_ready_agents codex
  hold_fake_agent

  run_onboarding_async $'2\n'

  for i in {1..30}; do
    primary="$(plist_raw "$APP_DIR/agent/preferences.json" primaryAgent 2>/dev/null || true)"
    [[ "$primary" == "codex" && -f "$FAKE_HOLD_FILE" ]] && break
    sleep 0.2
  done

  assert_eq "$primary" "codex" "primary preference is saved before the interactive cli exits"
  pid="$(cat "$FAKE_HOLD_FILE")"
  kill -0 "$pid" 2>/dev/null || fail "interactive fake codex should still be running after completion"

  touch "$FAKE_RELEASE_FILE"
  finish_onboarding_async

  assert_eq "$RUN_STATUS" "0" "async onboarding status"
  assert_contains "$(cat "$FAKE_LOG")" "codex:login status" "codex readiness uses polling status"
  assert_eq "$(plist_raw "$STATE_FILE" phase)" "complete" "state phase remains complete"
}

test_missing_codex_install_then_polling_completes() {
  local primary pid i
  setup_case codex-post-install-polling
  add_fake_installer_for_agent codex
  set_ready_agents codex
  hold_fake_agent

  run_onboarding_async $'2\ny\n'

  for i in {1..30}; do
    primary="$(plist_raw "$APP_DIR/agent/preferences.json" primaryAgent 2>/dev/null || true)"
    [[ "$primary" == "codex" && -f "$FAKE_HOLD_FILE" ]] && break
    sleep 0.2
  done

  assert_eq "$primary" "codex" "post-install polling saves primary before the interactive cli exits"
  pid="$(cat "$FAKE_HOLD_FILE")"
  kill -0 "$pid" 2>/dev/null || fail "post-install interactive codex should still be running after completion"

  touch "$FAKE_RELEASE_FILE"
  finish_onboarding_async

  assert_eq "$RUN_STATUS" "0" "post-install onboarding status"
  assert_contains "$RUN_OUTPUT" "Install complete. Re-scanning..." "post-install rescan message"
  assert_contains "$RUN_OUTPUT" "Codex found at" "installed codex is found after rescan"
  assert_contains "$(cat "$FAKE_LOG")" "codex:login status" "post-install codex readiness uses polling status"
  assert_contains "$(cat "$APP_DIR/onboarding/agent-cli-events.jsonl")" '"event":"install_succeeded"' "install success is recorded"
  assert_eq "$(plist_raw "$STATE_FILE" phase)" "complete" "post-install state phase is complete"
}

test_antigravity_launch_starts_interactive_cli_without_prompt() {
  setup_case antigravity-installed
  add_fake_agent antigravity

  run_onboarding $'3\n2\n'

  assert_eq "$RUN_STATUS" "1" "exit-for-now status"
  assert_contains "$RUN_OUTPUT" "3. Antigravity [installed]" "installed antigravity option"
  assert_contains "$RUN_OUTPUT" "Starting Antigravity for Zebra onboarding." "antigravity launches"
  assert_contains "$(cat "$FAKE_LOG")" "antigravity:" "agy launches interactively"
  [[ "$(cat "$FAKE_LOG")" != *"--prompt-interactive"* ]] || fail "agy onboarding launch should not pass a prompt"
  [[ "$(cat "$FAKE_LOG")" != *"--add-dir"* ]] || fail "agy onboarding launch should not add a directory"
  [[ "$(cat "$FAKE_LOG")" != *"--cwd"* ]] || fail "agy launch should not include --cwd"
  [[ "$(cat "$FAKE_LOG")" != *"--print"* ]] || fail "agy onboarding readiness should not use print smoke"
  [[ "$(cat "$FAKE_LOG")" != *" -p "* ]] || fail "agy onboarding should not use print shorthand"
  [[ ! -f "$APP_DIR/agent/preferences.json" ]] || fail "primary preference should not be saved before mark-ready"
  assert_eq "$(plist_raw "$STATE_FILE" selectedAgent)" "antigravity" "selected agent is persisted"
}

test_antigravity_auth_log_completes_onboarding() {
  local pid
  setup_case antigravity-ready
  add_fake_agent antigravity
  hold_fake_agent

  run_onboarding_async $'3\n'

  wait_for_fake_agent_hold
  write_antigravity_ready_state
  wait_for_primary_agent antigravity

  pid="$(cat "$FAKE_HOLD_FILE")"
  kill -0 "$pid" 2>/dev/null || fail "interactive fake antigravity should still be running after completion"
  touch "$FAKE_RELEASE_FILE"
  finish_onboarding_async

  assert_eq "$RUN_STATUS" "0" "ready antigravity status"
  [[ "$(cat "$FAKE_LOG")" != *"--print"* ]] || fail "agy readiness should use auth log instead of print smoke"
  assert_eq "$(plist_raw "$STATE_FILE" phase)" "complete" "state phase is complete"
  assert_eq "$(plist_raw "$APP_DIR/agent/preferences.json" primaryAgent)" "antigravity" "primary preference is saved after readiness"
}

test_antigravity_stale_auth_log_does_not_complete_until_fresh_event() {
  local primary pid
  setup_case antigravity-stale-log
  add_fake_agent antigravity
  write_antigravity_ready_state
  hold_fake_agent

  run_onboarding_async $'3\n'

  wait_for_fake_agent_hold
  sleep 2
  primary="$(plist_raw "$APP_DIR/agent/preferences.json" primaryAgent 2>/dev/null || true)"
  [[ -z "$primary" ]] || fail "stale antigravity auth log should not complete onboarding"

  write_antigravity_ready_state
  wait_for_primary_agent antigravity

  pid="$(cat "$FAKE_HOLD_FILE")"
  kill -0 "$pid" 2>/dev/null || fail "interactive fake antigravity should still be running after fresh auth event"
  touch "$FAKE_RELEASE_FILE"
  finish_onboarding_async

  assert_eq "$RUN_STATUS" "0" "fresh antigravity auth event status"
  assert_eq "$(plist_raw "$STATE_FILE" phase)" "complete" "state phase is complete after fresh auth event"
}

test_mark_ready_persists_primary_agent() {
  setup_case mark-ready
  write_state agent_working run-ready antigravity

  run_mark_ready antigravity run-ready

  assert_eq "$RUN_STATUS" "0" "mark-ready status"
  assert_contains "$RUN_OUTPUT" "Zebra onboarding marked ready for Antigravity." "ready message"
  assert_eq "$(plist_raw "$STATE_FILE" phase)" "complete" "state phase is complete"
  assert_eq "$(plist_raw "$APP_DIR/agent/preferences.json" primaryAgent)" "antigravity" "primary preference is saved after mark-ready"
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
test_claude_status_probe_completes_onboarding
test_codex_status_probe_completes_onboarding
test_codex_polling_completes_while_cli_is_still_running
test_missing_codex_install_then_polling_completes
test_antigravity_launch_starts_interactive_cli_without_prompt
test_antigravity_auth_log_completes_onboarding
test_antigravity_stale_auth_log_does_not_complete_until_fresh_event
test_mark_ready_persists_primary_agent
test_complete_state_exits_without_scan

printf 'PASS: zebra agent onboarding resume\n'
