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
CONTINUE_COMMAND_FILE=""
TEST_ONBOARDING_LANGUAGE="en"
TEST_FORCE_CODEX_OFFICIAL_INSTALLER_FAILURE="0"

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

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"
  [[ "$haystack" != *"$needle"* ]] || fail "$label: unexpected <$needle>"
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
  CONTINUE_COMMAND_FILE=""
  TEST_ONBOARDING_LANGUAGE="en"
  TEST_FORCE_CODEX_OFFICIAL_INSTALLER_FAILURE="0"
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

display_name_for_agent() {
  local agent="$1"
  case "$agent" in
    claude) printf 'Claude Code' ;;
    codex) printf 'Codex' ;;
    antigravity) printf 'Antigravity' ;;
    *) fail "unknown display agent: $agent" ;;
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
  cat > "$HOME_DIR/.local/bin/npm" <<'FAKE'
#!/usr/bin/env bash
printf 'unexpected npm fallback\n' >&2
exit 127
FAKE
  chmod +x "$HOME_DIR/.local/bin/npm"
  cat > "$HOME_DIR/.local/bin/brew" <<'FAKE'
#!/usr/bin/env bash
printf 'unexpected brew fallback\n' >&2
exit 127
FAKE
  chmod +x "$HOME_DIR/.local/bin/brew"
}

add_fake_codex_standalone_release_installer() {
  local binary source release_dir target archive
  binary="$(fake_agent_binary_name codex)"
  mkdir -p "$CASE_DIR/install-source" "$CASE_DIR/releases"
  source="$CASE_DIR/install-source/$binary"
  write_fake_agent codex "$source"
  for target in aarch64-apple-darwin x86_64-apple-darwin; do
    release_dir="$CASE_DIR/releases/$target"
    mkdir -p "$release_dir"
    cp "$source" "$release_dir/codex-$target"
    chmod +x "$release_dir/codex-$target"
    archive="$CASE_DIR/releases/codex-$target.tar.gz"
    tar -czf "$archive" -C "$release_dir" "codex-$target"
  done
  cat > "$HOME_DIR/.local/bin/curl" <<FAKE
#!/usr/bin/env bash
set -euo pipefail
for arg in "\$@"; do
  case "\$arg" in
    https://chatgpt.com/codex/install.sh)
      printf 'simulated chatgpt installer failure\n' >&2
      exit 56
      ;;
  esac
done
output=""
url=""
while [[ "\$#" -gt 0 ]]; do
  case "\$1" in
    -o)
      output="\${2:-}"
      shift 2
      ;;
    http*)
      url="\$1"
      shift
      ;;
    *)
      shift
      ;;
  esac
done
case "\$url" in
  *codex-aarch64-apple-darwin.tar.gz)
    cp "$CASE_DIR/releases/codex-aarch64-apple-darwin.tar.gz" "\$output"
    ;;
  *codex-x86_64-apple-darwin.tar.gz)
    cp "$CASE_DIR/releases/codex-x86_64-apple-darwin.tar.gz" "\$output"
    ;;
  *)
    printf 'unexpected curl url: %s\n' "\$url" >&2
    exit 22
    ;;
esac
FAKE
  chmod +x "$HOME_DIR/.local/bin/curl"
}

add_fake_codex_official_and_standalone_installers() {
  local binary source release_dir target archive
  binary="$(fake_agent_binary_name codex)"
  mkdir -p "$CASE_DIR/install-source" "$CASE_DIR/releases"
  source="$CASE_DIR/install-source/$binary"
  write_fake_agent codex "$source"
  for target in aarch64-apple-darwin x86_64-apple-darwin; do
    release_dir="$CASE_DIR/releases/$target"
    mkdir -p "$release_dir"
    cp "$source" "$release_dir/codex-$target"
    chmod +x "$release_dir/codex-$target"
    archive="$CASE_DIR/releases/codex-$target.tar.gz"
    tar -czf "$archive" -C "$release_dir" "codex-$target"
  done
  cat > "$HOME_DIR/.local/bin/curl" <<FAKE
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >> "$CASE_DIR/curl.log"
for arg in "\$@"; do
  case "\$arg" in
    https://chatgpt.com/codex/install.sh)
      cat <<'INSTALL'
#!/usr/bin/env sh
set -eu
mkdir -p "\$HOME/.local/bin"
cat > "\$HOME/.local/bin/codex" <<'CODEX'
#!/usr/bin/env bash
printf 'official codex should not run\n' >&2
exit 66
CODEX
chmod +x "\$HOME/.local/bin/codex"
INSTALL
      exit 0
      ;;
  esac
done
output=""
url=""
while [[ "\$#" -gt 0 ]]; do
  case "\$1" in
    -o)
      output="\${2:-}"
      shift 2
      ;;
    http*)
      url="\$1"
      shift
      ;;
    *)
      shift
      ;;
  esac
done
case "\$url" in
  *codex-aarch64-apple-darwin.tar.gz)
    cp "$CASE_DIR/releases/codex-aarch64-apple-darwin.tar.gz" "\$output"
    ;;
  *codex-x86_64-apple-darwin.tar.gz)
    cp "$CASE_DIR/releases/codex-x86_64-apple-darwin.tar.gz" "\$output"
    ;;
  *)
    printf 'unexpected curl url: %s\n' "\$url" >&2
    exit 22
    ;;
esac
FAKE
  chmod +x "$HOME_DIR/.local/bin/curl"
}

add_fake_codex_official_hidden_and_standalone_installers() {
  local binary source release_dir target archive
  binary="$(fake_agent_binary_name codex)"
  mkdir -p "$CASE_DIR/install-source" "$CASE_DIR/releases"
  source="$CASE_DIR/install-source/$binary"
  write_fake_agent codex "$source"
  for target in aarch64-apple-darwin x86_64-apple-darwin; do
    release_dir="$CASE_DIR/releases/$target"
    mkdir -p "$release_dir"
    cp "$source" "$release_dir/codex-$target"
    chmod +x "$release_dir/codex-$target"
    archive="$CASE_DIR/releases/codex-$target.tar.gz"
    tar -czf "$archive" -C "$release_dir" "codex-$target"
  done
  cat > "$HOME_DIR/.local/bin/curl" <<FAKE
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >> "$CASE_DIR/curl.log"
for arg in "\$@"; do
  case "\$arg" in
    https://chatgpt.com/codex/install.sh)
      cat <<'INSTALL'
#!/usr/bin/env sh
set -eu
mkdir -p "\$HOME/.codex/bin"
cp "$source" "\$HOME/.codex/bin/codex"
chmod +x "\$HOME/.codex/bin/codex"
INSTALL
      exit 0
      ;;
  esac
done
output=""
url=""
while [[ "\$#" -gt 0 ]]; do
  case "\$1" in
    -o)
      output="\${2:-}"
      shift 2
      ;;
    http*)
      url="\$1"
      shift
      ;;
    *)
      shift
      ;;
  esac
done
case "\$url" in
  *codex-aarch64-apple-darwin.tar.gz)
    cp "$CASE_DIR/releases/codex-aarch64-apple-darwin.tar.gz" "\$output"
    ;;
  *codex-x86_64-apple-darwin.tar.gz)
    cp "$CASE_DIR/releases/codex-x86_64-apple-darwin.tar.gz" "\$output"
    ;;
  *)
    printf 'unexpected curl url: %s\n' "\$url" >&2
    exit 22
    ;;
esac
FAKE
  chmod +x "$HOME_DIR/.local/bin/curl"
}

add_fake_claude_hidden_installer() {
  local source
  mkdir -p "$CASE_DIR/install-source"
  source="$CASE_DIR/install-source/claude"
  write_fake_agent claude "$source"
  cat > "$HOME_DIR/.local/bin/curl" <<FAKE
#!/usr/bin/env bash
set -euo pipefail
for arg in "\$@"; do
  case "\$arg" in
    https://claude.ai/install.sh)
      cat <<'INSTALL'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p "\$HOME/.claude/local"
cp "$source" "\$HOME/.claude/local/claude"
chmod +x "\$HOME/.claude/local/claude"
INSTALL
      exit 0
      ;;
  esac
done
printf 'unexpected curl args: %s\n' "\$*" >&2
exit 22
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

write_continue_command_file() {
  CONTINUE_COMMAND_FILE="$CASE_DIR/chained-step2.sh"
  cat > "$CONTINUE_COMMAND_FILE" <<'CHAIN'
#!/usr/bin/env bash
set -euo pipefail
printf 'chain:%s:%s:%s\n' "${ZEBRA_SELECTED_AGENT:?}" "${ZEBRA_AGENT_EXECUTABLE:?}" "$PWD" >> "${ZEBRA_FAKE_AGENT_LOG:?}"
"$ZEBRA_AGENT_EXECUTABLE" chained-step2 "$ZEBRA_SELECTED_AGENT"
CHAIN
  chmod 600 "$CONTINUE_COMMAND_FILE"
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
    ZEBRA_ONBOARDING_LANGUAGE="$TEST_ONBOARDING_LANGUAGE" \
    ZEBRA_AGENT_ONBOARDING_FORCE_CODEX_OFFICIAL_INSTALLER_FAILURE="$TEST_FORCE_CODEX_OFFICIAL_INSTALLER_FAILURE" \
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

run_onboarding_args() {
  local input="$1"
  local output_file="$CASE_DIR/output-args.txt"
  shift
  set +e
  HOME="$HOME_DIR" \
    ZEBRA_APP_SUPPORT_DIR="$APP_DIR" \
    ZEBRA_AGENT_ONBOARDING_INCLUDE_GLOBAL_PATHS=0 \
    ZEBRA_AGENT_READINESS_POLL_INTERVAL_SECONDS=1 \
    ZEBRA_AGENT_ANTIGRAVITY_AUTH_CHECK_BACKOFF_SECONDS=1 \
    ZEBRA_ONBOARDING_LANGUAGE="$TEST_ONBOARDING_LANGUAGE" \
    ZEBRA_AGENT_ONBOARDING_FORCE_CODEX_OFFICIAL_INSTALLER_FAILURE="$TEST_FORCE_CODEX_OFFICIAL_INSTALLER_FAILURE" \
    ZEBRA_FAKE_AGENT_LOG="$FAKE_LOG" \
    ZEBRA_FAKE_READY_AGENTS="$READY_AGENTS" \
    ZEBRA_FAKE_HOLD_FILE="$FAKE_HOLD_FILE" \
    ZEBRA_FAKE_RELEASE_FILE="$FAKE_RELEASE_FILE" \
    PATH="/usr/bin:/bin" \
    "$SCRIPT" "$@" >"$output_file" 2>&1 <<<"$input"
  RUN_STATUS=$?
  set -e
  RUN_OUTPUT="$(cat "$output_file")"
}

run_onboarding_chained() {
  local input="$1"
  local output_file="$CASE_DIR/output-chained.txt"
  [[ -n "$CONTINUE_COMMAND_FILE" ]] || fail "continue command file was not prepared"
  set +e
  HOME="$HOME_DIR" \
    ZEBRA_APP_SUPPORT_DIR="$APP_DIR" \
    ZEBRA_AGENT_ONBOARDING_INCLUDE_GLOBAL_PATHS=0 \
    ZEBRA_AGENT_READINESS_POLL_INTERVAL_SECONDS=1 \
    ZEBRA_AGENT_ANTIGRAVITY_AUTH_CHECK_BACKOFF_SECONDS=1 \
    ZEBRA_ONBOARDING_LANGUAGE="$TEST_ONBOARDING_LANGUAGE" \
    ZEBRA_AGENT_ONBOARDING_FORCE_CODEX_OFFICIAL_INSTALLER_FAILURE="$TEST_FORCE_CODEX_OFFICIAL_INSTALLER_FAILURE" \
    ZEBRA_FAKE_AGENT_LOG="$FAKE_LOG" \
    ZEBRA_FAKE_READY_AGENTS="$READY_AGENTS" \
    ZEBRA_FAKE_HOLD_FILE="$FAKE_HOLD_FILE" \
    ZEBRA_FAKE_RELEASE_FILE="$FAKE_RELEASE_FILE" \
    PATH="/usr/bin:/bin" \
    "$SCRIPT" run --cwd "$WORK_DIR" --continue-with-command-file "$CONTINUE_COMMAND_FILE" >"$output_file" 2>&1 <<<"$input"
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
    ZEBRA_ONBOARDING_LANGUAGE="$TEST_ONBOARDING_LANGUAGE" \
    ZEBRA_AGENT_ONBOARDING_FORCE_CODEX_OFFICIAL_INSTALLER_FAILURE="$TEST_FORCE_CODEX_OFFICIAL_INSTALLER_FAILURE" \
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
    ZEBRA_ONBOARDING_LANGUAGE="$TEST_ONBOARDING_LANGUAGE" \
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

  run_onboarding ''

  assert_eq "$RUN_STATUS" "1" "no-selection status"
  assert_contains "$RUN_OUTPUT" "Resuming Zebra agent onboarding for Antigravity." "resume message"
  assert_contains "$RUN_OUTPUT" $'Resuming Zebra agent onboarding for Antigravity.\n\nChecking Antigravity readiness...' "resume message keeps paragraph break"
  assert_contains "$RUN_OUTPUT" "Antigravity did not finish Zebra setup." "continue menu"
  assert_contains "$RUN_OUTPUT" "2. Choose another agent" "alternate agent option"
  assert_not_contains "$RUN_OUTPUT" "Exit for now" "continue menu does not include exit"
  assert_eq "$(plist_raw "$STATE_FILE" runId)" "run-waiting" "run id is preserved"
  assert_eq "$(plist_raw "$STATE_FILE" phase)" "waiting_for_continue" "phase remains waiting"
  assert_eq "$(cat "$FAKE_LOG")" "" "agent is not relaunched automatically"
}

test_agent_working_resumes_to_continue_menu() {
  setup_case working
  write_preferences antigravity
  write_state agent_working run-working antigravity

  run_onboarding ''

  assert_eq "$RUN_STATUS" "1" "no-selection status"
  assert_contains "$RUN_OUTPUT" "Resuming Zebra agent onboarding for Antigravity." "resume message"
  assert_contains "$RUN_OUTPUT" "Antigravity did not finish Zebra setup." "continue menu"
  assert_contains "$RUN_OUTPUT" "2. Choose another agent" "alternate agent option"
  assert_not_contains "$RUN_OUTPUT" "Exit for now" "continue menu does not include exit"
  assert_eq "$(plist_raw "$STATE_FILE" runId)" "run-working" "run id is preserved"
  assert_eq "$(plist_raw "$STATE_FILE" phase)" "waiting_for_continue" "working phase moves to waiting"
  assert_eq "$(cat "$FAKE_LOG")" "" "agent is not relaunched automatically"
}

test_waiting_for_continue_can_choose_another_agent() {
  setup_case waiting-choose-another
  write_preferences antigravity
  write_state waiting_for_continue run-waiting-other antigravity
  add_fake_agent codex
  set_ready_agents codex

  run_onboarding $'2\n2\n'

  assert_eq "$RUN_STATUS" "0" "alternate agent completes"
  assert_contains "$RUN_OUTPUT" "Choose another agent for Zebra:" "alternate menu"
  assert_contains "$RUN_OUTPUT" "2. Codex [installed]" "installed alternate option"
  assert_contains "$(cat "$FAKE_LOG")" "codex:" "alternate agent launches"
  [[ "$(cat "$FAKE_LOG")" != *"antigravity:"* ]] || fail "failed agent should not relaunch when choosing another"
  assert_eq "$(plist_raw "$STATE_FILE" phase)" "complete" "alternate agent completes state"
  assert_eq "$(plist_raw "$APP_DIR/agent/preferences.json" primaryAgent)" "codex" "alternate agent is saved"
}

test_choose_install_target_resumes_install_menu() {
  setup_case install-target
  write_state choose_install_target run-install

  run_onboarding $'3\nn\n'

  assert_eq "$RUN_STATUS" "1" "declined install exit status"
  assert_contains "$RUN_OUTPUT" "Resuming Zebra agent onboarding at install selection." "resume message"
  assert_contains "$RUN_OUTPUT" "Zebra will run the installer command for Antigravity:" "install prompt"
  assert_not_contains "$RUN_OUTPUT" "Exit for now" "install failure menu does not include exit"
  assert_eq "$(plist_raw "$STATE_FILE" runId)" "run-install" "run id is preserved"
  assert_eq "$(plist_raw "$STATE_FILE" phase)" "choose_install_target" "phase remains install selection"
}

test_fresh_choice_lists_missing_agents() {
  setup_case fresh-missing
  add_fake_agent codex

  run_onboarding $'3\nn\n'

  assert_eq "$RUN_STATUS" "1" "declined missing-agent install status"
  assert_contains "$RUN_OUTPUT" "Which agent should Zebra use by default?" "primary prompt"
  assert_contains "$RUN_OUTPUT" "2. Codex [installed]" "installed option"
  assert_contains "$RUN_OUTPUT" "3. Antigravity [not installed]" "missing option"
  assert_contains "$RUN_OUTPUT" "Zebra will run the installer command for Antigravity:" "missing selection installs"
  assert_not_contains "$RUN_OUTPUT" "Exit for now" "install failure menu does not include exit"
  assert_eq "$(plist_raw "$STATE_FILE" phase)" "choose_primary" "declined install returns to primary choice state"
  assert_eq "$(cat "$FAKE_LOG")" "" "installed agent is not launched when missing agent is selected"
}

test_korean_language_keeps_agent_terms_in_english() {
  setup_case korean-language
  TEST_ONBOARDING_LANGUAGE="ko"
  add_fake_agent codex

  run_onboarding $'2\n'

  assert_eq "$RUN_STATUS" "1" "korean no-selection status"
  assert_contains "$RUN_OUTPUT" "어떤 agent를 Zebra의 default로 사용할까요?" "korean primary prompt"
  assert_contains "$RUN_OUTPUT" "2. Codex [installed]" "technical menu terms stay English"
  assert_contains "$RUN_OUTPUT" "Zebra onboarding을 위해 Codex를 시작합니다." "korean launch message"
  assert_contains "$RUN_OUTPUT" "provider CLI" "technical CLI term stays English"
  assert_not_contains "$RUN_OUTPUT" "Which agent should Zebra use by default?" "english primary prompt is not used"
}

test_korean_language_applies_to_unknown_option_error() {
  setup_case korean-unknown-option

  run_onboarding_args '' run --language ko --unknown

  assert_eq "$RUN_STATUS" "2" "korean unknown option status"
  assert_contains "$RUN_OUTPUT" "알 수 없는 option: --unknown" "korean unknown option message"
  assert_not_contains "$RUN_OUTPUT" "unknown option: --unknown" "english unknown option is not used"
}

assert_declined_install_can_choose_another_agent() {
  local failed_agent="$1"
  local failed_selection="$2"
  local alternate_agent="$3"
  local alternate_selection="$4"
  local failed_display alternate_display
  failed_display="$(display_name_for_agent "$failed_agent")"
  alternate_display="$(display_name_for_agent "$alternate_agent")"
  setup_case "declined-install-${failed_agent}-choose-${alternate_agent}"
  add_fake_agent "$alternate_agent"
  set_ready_agents "$alternate_agent"

  run_onboarding "$(printf '%s\nn\n2\n%s\n' "$failed_selection" "$alternate_selection")"

  assert_eq "$RUN_STATUS" "0" "$failed_agent alternate agent completes after declined install"
  assert_contains "$RUN_OUTPUT" "$failed_display install did not complete." "$failed_agent install recovery menu"
  assert_contains "$RUN_OUTPUT" "2. Choose another agent" "$failed_agent alternate agent option"
  assert_contains "$RUN_OUTPUT" "Choose another agent for Zebra:" "$failed_agent alternate menu"
  assert_contains "$(cat "$FAKE_LOG")" "$alternate_agent:" "$failed_agent alternate agent launches"
  [[ "$(cat "$FAKE_LOG")" != *"$failed_agent:"* ]] || fail "$failed_agent should not launch when choosing another"
  [[ "$RUN_OUTPUT" != *"Zebra will run the installer command for $alternate_display:"* ]] || fail "handled alternate selection should not start a second $alternate_agent install flow"
  assert_eq "$(plist_raw "$STATE_FILE" phase)" "complete" "$failed_agent alternate agent completes state"
  assert_eq "$(plist_raw "$APP_DIR/agent/preferences.json" primaryAgent)" "$alternate_agent" "$failed_agent alternate agent is saved"
}

assert_failed_install_resume_can_choose_another_agent() {
  local failed_agent="$1"
  local alternate_agent="$2"
  local alternate_selection="$3"
  local failed_display alternate_display
  failed_display="$(display_name_for_agent "$failed_agent")"
  alternate_display="$(display_name_for_agent "$alternate_agent")"
  setup_case "failed-install-${failed_agent}-resume-choose-${alternate_agent}"
  write_state failed "run-failed-${failed_agent}" "$failed_agent"
  add_fake_agent "$alternate_agent"
  set_ready_agents "$alternate_agent"

  run_onboarding "$(printf '2\n%s\n' "$alternate_selection")"

  assert_eq "$RUN_STATUS" "0" "$failed_agent alternate agent completes from failed install resume"
  assert_contains "$RUN_OUTPUT" "Resuming Zebra agent onboarding after an interrupted $failed_display install." "$failed_agent failed install resume message"
  assert_contains "$RUN_OUTPUT" "$failed_display install did not complete." "$failed_agent install recovery menu"
  assert_contains "$RUN_OUTPUT" "Choose another agent for Zebra:" "$failed_agent alternate menu"
  assert_contains "$(cat "$FAKE_LOG")" "$alternate_agent:" "$failed_agent alternate agent launches"
  [[ "$(cat "$FAKE_LOG")" != *"$failed_agent:"* ]] || fail "$failed_agent should not launch when resuming and choosing another"
  [[ "$RUN_OUTPUT" != *"Zebra will run the installer command for $alternate_display:"* ]] || fail "handled alternate selection should not start a second $alternate_agent install flow"
  assert_eq "$(plist_raw "$STATE_FILE" phase)" "complete" "$failed_agent alternate agent completes state"
  assert_eq "$(plist_raw "$APP_DIR/agent/preferences.json" primaryAgent)" "$alternate_agent" "$failed_agent alternate agent is saved"
}

test_declined_install_can_choose_another_agent_for_any_agent() {
  assert_declined_install_can_choose_another_agent claude 1 codex 1
  assert_declined_install_can_choose_another_agent codex 2 claude 1
  assert_declined_install_can_choose_another_agent antigravity 3 codex 2
}

test_failed_install_resume_can_choose_another_agent_for_any_agent() {
  assert_failed_install_resume_can_choose_another_agent claude codex 1
  assert_failed_install_resume_can_choose_another_agent codex claude 1
  assert_failed_install_resume_can_choose_another_agent antigravity codex 2
}

test_fresh_choice_launches_installed_selection() {
  setup_case fresh-installed
  add_fake_agent codex

  run_onboarding $'2\n'

  assert_eq "$RUN_STATUS" "1" "no-selection status"
  assert_contains "$RUN_OUTPUT" "2. Codex [installed]" "installed option"
  assert_contains "$RUN_OUTPUT" "Starting Codex for Zebra onboarding." "selected installed agent launches"
  assert_not_contains "$RUN_OUTPUT" "Exit for now" "continue menu does not include exit"
  assert_contains "$(cat "$FAKE_LOG")" "codex:" "fake codex launched"
  assert_contains "$(cat "$FAKE_LOG")" "codex:login status" "codex readiness uses login status"
  [[ ! -f "$APP_DIR/agent/preferences.json" ]] || fail "primary preference should not be saved before mark-ready"
  assert_eq "$(plist_raw "$STATE_FILE" selectedAgent)" "codex" "selected agent is persisted"
  assert_eq "$(plist_raw "$STATE_FILE" phase)" "waiting_for_continue" "launch exit moves to continue menu"
}

test_chained_step2_launches_selected_agent_without_readiness_watcher() {
  local fake_log events primary_path expected_codex_path expected_work_dir
  setup_case chained-codex
  add_fake_agent codex
  set_ready_agents codex
  write_continue_command_file

  run_onboarding_chained $'2\n'

  fake_log="$(cat "$FAKE_LOG")"
  events="$(cat "$APP_DIR/onboarding/agent-cli-events.jsonl")"
  primary_path="$(plist_raw "$APP_DIR/agent/preferences.json" primaryAgentExecutablePath)"
  expected_codex_path="$(cd "$(dirname "$HOME_DIR/.local/bin/codex")" && pwd)/codex"
  expected_work_dir="$(cd "$WORK_DIR" && pwd)"
  assert_eq "$RUN_STATUS" "0" "chained codex status"
  assert_contains "$RUN_OUTPUT" "Starting Codex for Zebra onboarding." "chained launch message"
  assert_contains "$fake_log" "chain:codex:$expected_codex_path:$expected_work_dir" "command file receives selected executable"
  assert_contains "$fake_log" "codex:chained-step2 codex" "command file launches selected executable"
  assert_not_contains "$fake_log" "codex:login status" "chained flow skips codex readiness probe"
  assert_contains "$events" '"event":"agent_launch_chained_step2_started"' "chained start event is recorded"
  assert_not_contains "$events" '"event":"agent_readiness_watch_started"' "chained flow skips readiness watcher"
  assert_eq "$(plist_raw "$STATE_FILE" phase)" "complete" "chained flow completes agent state before step2"
  assert_eq "$(plist_raw "$APP_DIR/agent/preferences.json" primaryAgent)" "codex" "chained flow saves primary"
  assert_eq "$primary_path" "$expected_codex_path" "chained flow saves selected executable"
}

test_chained_step2_resume_agent_working_relaunches_command_file() {
  local fake_log expected_codex_path expected_work_dir
  setup_case chained-resume
  write_preferences codex
  write_state agent_working run-chained codex
  add_fake_agent codex
  write_continue_command_file

  run_onboarding_chained ''

  fake_log="$(cat "$FAKE_LOG")"
  expected_codex_path="$(cd "$(dirname "$HOME_DIR/.local/bin/codex")" && pwd)/codex"
  expected_work_dir="$(cd "$WORK_DIR" && pwd)"
  assert_eq "$RUN_STATUS" "0" "chained resume status"
  assert_contains "$RUN_OUTPUT" "Resuming Zebra agent onboarding for Codex." "chained resume message"
  assert_not_contains "$RUN_OUTPUT" "Codex did not finish Zebra setup." "chained resume does not show continue menu"
  assert_contains "$fake_log" "chain:codex:$expected_codex_path:$expected_work_dir" "resume command file receives selected executable"
  assert_contains "$fake_log" "codex:chained-step2 codex" "resume command file launches selected executable"
  assert_not_contains "$fake_log" "codex:login status" "chained resume skips readiness probe"
  assert_eq "$(plist_raw "$STATE_FILE" runId)" "run-chained" "chained resume preserves run id"
  assert_eq "$(plist_raw "$STATE_FILE" phase)" "complete" "chained resume completes state"
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

test_missing_claude_install_exposes_hidden_binary_to_new_shells() {
  local primary pid i resolved_claude
  setup_case claude-hidden-post-install
  add_fake_claude_hidden_installer
  set_ready_agents claude
  hold_fake_agent

  run_onboarding_async $'1\ny\n'

  for i in {1..30}; do
    primary="$(plist_raw "$APP_DIR/agent/preferences.json" primaryAgent 2>/dev/null || true)"
    [[ "$primary" == "claude" && -f "$FAKE_HOLD_FILE" ]] && break
    sleep 0.2
  done

  assert_eq "$primary" "claude" "hidden claude install saves primary before the interactive cli exits"
  pid="$(cat "$FAKE_HOLD_FILE")"
  kill -0 "$pid" 2>/dev/null || fail "hidden claude interactive cli should still be running after completion"

  touch "$FAKE_RELEASE_FILE"
  finish_onboarding_async

  assert_eq "$RUN_STATUS" "0" "hidden claude onboarding status"
  assert_contains "$RUN_OUTPUT" "Install complete. Re-scanning..." "hidden claude rescan message"
  assert_contains "$RUN_OUTPUT" "Claude Code found at" "hidden claude is found after exposure"
  [[ -L "$HOME_DIR/.local/bin/claude" ]] || fail "hidden claude install should be exposed through ~/.local/bin/claude"
  assert_contains "$RUN_OUTPUT" "Updated shell startup files so claude is available in new terminals." "hidden claude shell path message"
  assert_contains "$(cat "$FAKE_LOG")" "claude:auth status --json" "hidden claude readiness uses polling status"
  resolved_claude="$(HOME="$HOME_DIR" PATH="/usr/bin:/bin" /bin/zsh -lc 'command -v claude')"
  assert_eq "$resolved_claude" "$HOME_DIR/.local/bin/claude" "new zsh login shell can find claude"
  assert_eq "$(plist_raw "$STATE_FILE" phase)" "complete" "hidden claude state phase is complete"
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
  local primary pid i resolved_codex
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
  assert_contains "$RUN_OUTPUT" "Updated shell startup files so codex is available in new terminals." "post-install shell path message"
  assert_contains "$(cat "$FAKE_LOG")" "codex:login status" "post-install codex readiness uses polling status"
  assert_contains "$(cat "$APP_DIR/onboarding/agent-cli-events.jsonl")" '"event":"install_succeeded"' "install success is recorded"
  assert_contains "$(cat "$APP_DIR/onboarding/agent-cli-events.jsonl")" '"event":"shell_path_configured"' "shell path setup is recorded"
  assert_contains "$(cat "$HOME_DIR/.zprofile")" "# >>> Zebra agent CLI PATH >>>" "zprofile contains managed path block"
  assert_contains "$(cat "$HOME_DIR/.zprofile")" "$HOME_DIR/.local/bin" "zprofile includes installed codex directory"
  assert_contains "$(cat "$HOME_DIR/.config/fish/conf.d/zebra-agent-path.fish")" "$HOME_DIR/.local/bin" "fish config includes installed codex directory"
  resolved_codex="$(HOME="$HOME_DIR" PATH="/usr/bin:/bin" /bin/zsh -lc 'command -v codex')"
  assert_eq "$resolved_codex" "$HOME_DIR/.local/bin/codex" "new zsh login shell can find codex"
  assert_eq "$(plist_raw "$STATE_FILE" phase)" "complete" "post-install state phase is complete"
}

test_missing_codex_install_uses_standalone_when_package_managers_absent() {
  local primary pid i resolved_codex
  setup_case codex-standalone-fallback
  add_fake_codex_standalone_release_installer
  set_ready_agents codex
  hold_fake_agent

  run_onboarding_async $'2\ny\n'

  for i in {1..30}; do
    primary="$(plist_raw "$APP_DIR/agent/preferences.json" primaryAgent 2>/dev/null || true)"
    [[ "$primary" == "codex" && -f "$FAKE_HOLD_FILE" ]] && break
    sleep 0.2
  done

  assert_eq "$primary" "codex" "standalone fallback saves primary before the interactive cli exits"
  pid="$(cat "$FAKE_HOLD_FILE")"
  kill -0 "$pid" 2>/dev/null || fail "standalone fallback interactive codex should still be running after completion"

  touch "$FAKE_RELEASE_FILE"
  finish_onboarding_async

  assert_eq "$RUN_STATUS" "0" "standalone fallback onboarding status"
  assert_contains "$RUN_OUTPUT" "Install complete. Re-scanning..." "standalone fallback rescan message"
  assert_contains "$RUN_OUTPUT" "Codex found at" "standalone fallback codex is found after rescan"
  [[ -x "$HOME_DIR/.local/bin/codex" ]] || fail "standalone fallback should install codex to ~/.local/bin"
  assert_contains "$(cat "$FAKE_LOG")" "codex:login status" "standalone fallback codex readiness uses polling status"
  resolved_codex="$(HOME="$HOME_DIR" PATH="/usr/bin:/bin" /bin/zsh -lc 'command -v codex')"
  assert_eq "$resolved_codex" "$HOME_DIR/.local/bin/codex" "new zsh login shell can find standalone codex"
  assert_eq "$(plist_raw "$STATE_FILE" phase)" "complete" "standalone fallback state phase is complete"
}

test_codex_forced_official_failure_skips_successful_official_installer() {
  local primary pid i curl_log
  setup_case codex-force-official-failure
  add_fake_codex_official_and_standalone_installers
  TEST_FORCE_CODEX_OFFICIAL_INSTALLER_FAILURE="1"
  set_ready_agents codex
  hold_fake_agent

  run_onboarding_async $'2\ny\n'

  for i in {1..30}; do
    primary="$(plist_raw "$APP_DIR/agent/preferences.json" primaryAgent 2>/dev/null || true)"
    [[ "$primary" == "codex" && -f "$FAKE_HOLD_FILE" ]] && break
    sleep 0.2
  done

  assert_eq "$primary" "codex" "forced official failure saves primary before the interactive cli exits"
  pid="$(cat "$FAKE_HOLD_FILE")"
  kill -0 "$pid" 2>/dev/null || fail "forced official failure interactive codex should still be running after completion"

  touch "$FAKE_RELEASE_FILE"
  finish_onboarding_async

  assert_eq "$RUN_STATUS" "0" "forced official failure onboarding status"
  curl_log="$(cat "$CASE_DIR/curl.log")"
  assert_contains "$RUN_OUTPUT" "Codex official installer did not complete. Trying fallbacks..." "forced official failure explains official fallback"
  assert_contains "$RUN_OUTPUT" "npm was not found. Skipping npm fallback." "forced official failure explains missing npm"
  assert_contains "$RUN_OUTPUT" "brew was not found. Skipping Homebrew fallback." "forced official failure explains missing brew"
  assert_contains "$RUN_OUTPUT" "Installing Codex standalone binary from OpenAI GitHub Release..." "forced official failure explains standalone fallback"
  assert_contains "$RUN_OUTPUT" "Codex install succeeded via standalone." "forced official failure reports standalone success"
  assert_not_contains "$curl_log" "https://chatgpt.com/codex/install.sh" "forced official failure skips official installer"
  assert_contains "$curl_log" "github.com/openai/codex/releases/latest/download/codex-" "forced official failure downloads GitHub release"
  assert_contains "$(cat "$FAKE_LOG")" "codex:login status" "forced official failure codex readiness uses polling status"
  assert_eq "$(plist_raw "$STATE_FILE" phase)" "complete" "forced official failure state phase is complete"
}

test_codex_auto_exposes_hidden_official_install_to_new_shells() {
  local primary pid i curl_log resolved_codex
  setup_case codex-hidden-official
  add_fake_codex_official_hidden_and_standalone_installers
  set_ready_agents codex
  hold_fake_agent

  run_onboarding_async $'2\ny\n'

  for i in {1..30}; do
    primary="$(plist_raw "$APP_DIR/agent/preferences.json" primaryAgent 2>/dev/null || true)"
    [[ "$primary" == "codex" && -f "$FAKE_HOLD_FILE" ]] && break
    sleep 0.2
  done

  assert_eq "$primary" "codex" "hidden official install saves primary before the interactive cli exits"
  pid="$(cat "$FAKE_HOLD_FILE")"
  kill -0 "$pid" 2>/dev/null || fail "hidden official interactive codex should still be running after completion"

  touch "$FAKE_RELEASE_FILE"
  finish_onboarding_async

  assert_eq "$RUN_STATUS" "0" "hidden official onboarding status"
  curl_log="$(cat "$CASE_DIR/curl.log")"
  assert_contains "$curl_log" "https://chatgpt.com/codex/install.sh" "auto mode tries official installer first"
  assert_not_contains "$curl_log" "github.com/openai/codex/releases/latest/download/codex-" "visible hidden official install does not need GitHub fallback"
  [[ -L "$HOME_DIR/.local/bin/codex" ]] || fail "hidden codex install should be exposed through ~/.local/bin/codex"
  assert_contains "$(cat "$FAKE_LOG")" "codex:login status" "hidden official codex readiness uses polling status"
  resolved_codex="$(HOME="$HOME_DIR" PATH="/usr/bin:/bin" /bin/zsh -lc 'command -v codex')"
  assert_eq "$resolved_codex" "$HOME_DIR/.local/bin/codex" "new zsh login shell finds exposed hidden codex"
  assert_eq "$(plist_raw "$STATE_FILE" phase)" "complete" "hidden official state phase is complete"
}

test_antigravity_launch_starts_interactive_cli_without_prompt() {
  setup_case antigravity-installed
  add_fake_agent antigravity

  run_onboarding $'3\n'

  assert_eq "$RUN_STATUS" "1" "no-selection status"
  assert_contains "$RUN_OUTPUT" "3. Antigravity [installed]" "installed antigravity option"
  assert_contains "$RUN_OUTPUT" "Starting Antigravity for Zebra onboarding." "antigravity launches"
  assert_not_contains "$RUN_OUTPUT" "Exit for now" "continue menu does not include exit"
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
test_waiting_for_continue_can_choose_another_agent
test_choose_install_target_resumes_install_menu
test_fresh_choice_lists_missing_agents
test_korean_language_keeps_agent_terms_in_english
test_korean_language_applies_to_unknown_option_error
test_declined_install_can_choose_another_agent_for_any_agent
test_failed_install_resume_can_choose_another_agent_for_any_agent
test_fresh_choice_launches_installed_selection
test_chained_step2_launches_selected_agent_without_readiness_watcher
test_chained_step2_resume_agent_working_relaunches_command_file
test_claude_status_probe_completes_onboarding
test_missing_claude_install_exposes_hidden_binary_to_new_shells
test_codex_status_probe_completes_onboarding
test_codex_polling_completes_while_cli_is_still_running
test_missing_codex_install_then_polling_completes
test_missing_codex_install_uses_standalone_when_package_managers_absent
test_codex_forced_official_failure_skips_successful_official_installer
test_codex_auto_exposes_hidden_official_install_to_new_shells
test_antigravity_launch_starts_interactive_cli_without_prompt
test_antigravity_auth_log_completes_onboarding
test_antigravity_stale_auth_log_does_not_complete_until_fresh_event
test_mark_ready_persists_primary_agent
test_complete_state_exits_without_scan

printf 'PASS: zebra agent onboarding resume\n'
