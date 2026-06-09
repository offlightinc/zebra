# Zebra onboarding agent CLI scan plan

## Context

Zebra first-run onboarding should pick a primary AI agent before it starts
agent-driven setup work. The user may have one or more agent CLIs installed
already, may have accounts but no local CLI, or may have no provider account
yet. Zebra should not assume Claude Code is the only path.

The first supported terminal agents for this plan are:

- Claude Code (`claude`)
- Codex (`codex`)
- Antigravity (`agy`)

Gemini CLI is intentionally not part of this onboarding candidate set. If a
local `gemini` binary exists, ignore it for this flow unless a later product
decision explicitly re-adds it.

The goal is not to implement provider account creation inside Zebra. The goal
is to get the user to a selected, installed, runnable agent CLI, then let the
provider's official login/signup flow handle account creation and auth.

## Product Decision So Far

The onboarding flow should be:

```text
scan installed CLIs
-> 0 installed: ask which agent to install, then Zebra runs the install flow
-> 1 installed: auto-select it as primary
-> multiple installed: ask which agent should be primary
-> persist primary agent
-> launch the selected CLI in Zebra's agent terminal
-> provider CLI handles login/signup if needed
-> continue Zebra onboarding after the agent is ready
```

Important distinction:

- "No CLI installed" is Zebra's problem to route.
- "CLI installed but user is not logged in" is provider CLI's problem to route.
- "User has no provider account" is also provider CLI's login/signup flow's
  problem to route.

Zebra should not ask "Do you already have a Claude/Codex/Antigravity account?"
as a separate first-run branch in V1. That question does not change Zebra's
next local action: install the selected CLI if missing, then run it.

## Why This Shape

If the user has no account, launching the selected provider's CLI still lands
them in the same official login/signup path they would need to use from any
Zebra-made "create account" screen. Building a separate account-first flow in
Zebra adds provider-specific surface area without reducing the necessary
provider login/signup step.

The useful work Zebra can own is:

- discover which local agent CLIs are available;
- avoid asking when only one viable candidate exists;
- ask for a primary agent when there are multiple viable candidates;
- install the selected CLI when none are present or the selected one is
  missing;
- persist the primary agent choice;
- launch the selected agent with the right cwd, trust handling, and first
  prompt.

## Terminology

### Agent kind

The provider/tool identity Zebra understands:

```swift
enum ZebraAgentKind: String, CaseIterable, Identifiable, Sendable {
    case claude
    case codex
    case antigravity
}
```

This should not be named around Clawvisor. The same primary agent choice should
be usable by first-run onboarding, ChatPill, brain-sync recovery, email
connection recovery, and future agent launches.

### Result model

"Model" here means a Swift data model for scan results, not an AI model. It is
the structured result passed from scanner -> coordinator -> UI/terminal flow.

Suggested shape:

```swift
struct ZebraAgentInstallCandidate: Identifiable, Equatable, Sendable {
    let id: ZebraAgentKind
    let displayName: String
    let binaryName: String
    let executablePath: String?
    let appBundlePath: String?
    let version: String?
    let installState: ZebraAgentInstallState
    let authState: ZebraAgentAuthState
    let terminalLaunchable: Bool
    let recommendedAction: ZebraAgentOnboardingAction
}

enum ZebraAgentInstallState: Equatable, Sendable {
    case installed
    case missing
    case broken(reason: String)
}

enum ZebraAgentAuthState: Equatable, Sendable {
    case unknown
    case configPresent
    case probablySignedOut
}

enum ZebraAgentOnboardingAction: Equatable, Sendable {
    case launch
    case install
    case repairInstall
}
```

`authState` is intentionally weak in V1. It is only advisory copy for the
terminal flow, not a hard gate.

## Auth Validation Policy

V1 should avoid deep auth validation.

Allowed checks:

- Is the executable present?
- Is it executable?
- Can `--version` or an equivalent no-op version command return quickly?
- Is there a known local config/session file that suggests the user has run
  the tool before?

Avoid in V1:

- running commands that may start a full interactive login;
- trying to inspect provider tokens deeply;
- trying to prove subscription/account eligibility;
- opening provider-specific account APIs from Zebra;
- treating auth detection as a blocking pass/fail.

Reason: provider CLIs can open browsers, prompt in the terminal, hit Keychain,
or change behavior between versions. Zebra should not own that compatibility
surface during first-run onboarding.

The CLI itself should own login/signup. Zebra's terminal copy can say, in
effect: "If this tool asks you to sign in or create an account, complete that
provider flow and return here."

## Scenario Matrix

### 1. Primary agent already saved and CLI still exists

Example: `preferences.primaryAgent = codex`, and `codex` is found.

Expected behavior:

- Do not ask again.
- Use saved primary agent.
- Launch selected CLI in the agent terminal with the Zebra onboarding prompt.
- If the CLI asks for login/signup, let the provider flow proceed.

Implementation note:

- The saved preference should be validated against current scan output.
- If the saved agent is missing, drop into scenario 5.

### 2. No saved primary agent and exactly one CLI is installed

Example: only `claude` is found.

Expected behavior:

- Auto-select `claude`.
- Persist it as primary.
- Launch the onboarding agent terminal.

Rationale:

- Asking the user to choose when there is only one viable local option is
  unnecessary friction.

### 3. No saved primary agent and multiple CLIs are installed

Example: `claude`, `codex`, and `agy` are all found.

Expected behavior:

- Ask which one should be the primary agent.
- Persist the answer.
- Launch the selected CLI.

UX location:

- This can be done in a Zebra terminal setup script or a native onboarding UI.
- Since the current product direction emphasizes agent-terminal onboarding, the
  first implementation can ask inside a terminal pane.

Terminal sketch:

```text
Zebra found these agent CLIs:

  1. Claude Code       /opt/homebrew/bin/claude
  2. Codex             /opt/homebrew/bin/codex
  3. Antigravity       ~/.local/bin/agy

Which agent should Zebra use by default? [1-3]
```

### 4. No saved primary agent and no CLI is installed

Expected behavior:

- Ask which agent the user wants Zebra to install.
- Run the selected provider's official install flow from the Zebra terminal.
- Re-scan after install.
- If the selected CLI is now found, persist it as primary.
- Launch it.

Important: this is not "show install instructions and stop." Zebra should drive
the install flow after the user chooses the desired agent. The exact install
commands should be looked up from official provider docs during implementation,
not frozen in this planning document.

Terminal sketch:

```text
Zebra did not find a supported agent CLI.

Choose the agent you want Zebra to install:

  1. Claude Code
  2. Codex
  3. Antigravity

Selection: _
```

After selection:

```text
Installing Codex...
...
Install complete. Re-scanning...
Codex found at /opt/homebrew/bin/codex.
Starting Codex for Zebra onboarding...
```

### 5. Saved primary agent exists but its CLI is missing

Example: saved primary is `claude`, but `claude` is no longer found.

Expected behavior:

- Tell the user Zebra cannot find the previously selected agent.
- Offer:
  - reinstall that agent;
  - choose another installed agent if any exist;
  - choose a different agent to install.

This should not silently switch to another installed CLI. The primary agent is
a user preference, so if it disappears Zebra should ask before changing it.

### 6. CLI exists but user has no provider account

Expected behavior:

- Zebra launches the selected CLI.
- Provider CLI shows login/signup flow.
- User creates account or signs in through provider flow.
- Zebra onboarding continues after the agent is ready.

No separate Zebra account-detection branch is needed. "No account" and "not
logged in" look the same from Zebra's perspective in V1.

### 7. User has provider account but CLI is not installed

Expected behavior:

- Same as scenario 4.
- Zebra cannot reliably know account existence before the CLI/provider flow.
- User chooses an agent, Zebra installs it, CLI then asks them to sign in.

### 8. CLI install fails

Expected behavior:

- Show the failed command and a short reason if available.
- Offer retry.
- Offer choose another agent.
- Offer open/copy manual install instructions only as a fallback.

Zebra should keep the user in the onboarding flow instead of dropping them into
a dead end.

## Existing Zebra Code To Reuse

### Current agent enum

`Packages/ZebraVault/Sources/ZebraVault/MarkdownChatPill/MarkdownPillAgent.swift`
already has:

```swift
public enum MarkdownPillAgent: String, CaseIterable, Identifiable, Sendable {
    case codex
    case claude
    case gemini
}
```

This should be revised or superseded:

- remove/ignore Gemini for this onboarding path;
- add Antigravity;
- consider renaming to a more general `ZebraAgentKind` if it becomes the shared
  primary agent type.

Do not build first-run onboarding on `ZebraClawvisorAgent`; that enum is tied
to the Clawvisor email onboarding picker and includes rows like Claude Desktop
and Other Agents that are not the same as "terminal-launchable primary agent."

### Current launch command logic

`Packages/ZebraVault/Sources/ZebraVault/MarkdownChatPill/MarkdownChatPillCommand.swift`
already knows the different CLI launch conventions for Codex, Claude, and
Gemini:

- Codex: `codex -C <cwd> ...`
- Claude: `claude --append-system-prompt ...`
- Gemini: `gemini --prompt-interactive ...`

For this plan:

- keep the per-agent launch-contract idea;
- replace Gemini-specific launch support with Antigravity support using the
  official `agy -p <prompt> --cwd <cwd>` launch contract;
- keep trust/cwd safeguards;
- avoid hardcoding Clawvisor-specific prompts in the shared agent launcher.

### Current preference storage

`Packages/ZebraVault/Sources/ZebraVault/BrainSync/BrainSyncAgentPicker.swift`
currently stores:

```swift
zebra.brainSync.preferredAgent
```

The first-run primary agent should move to the shared durable preference file:

```text
~/Library/Application Support/zebra/agent/preferences.json
```

Then brain-sync and ChatPill can default to `primaryAgent` while still allowing
surface-specific overrides through `surfaceOverrides`.

### Current Clawvisor picker

`Packages/ZebraVault/Sources/ZebraVault/Email/ZebraClawvisorAgent.swift`
currently has:

- Claude Code
- Claude Desktop
- OpenClaw / Hermes
- Other agents

Only Claude Code is wired today. That picker is not enough for this first-run
primary-agent flow because:

- it is Clawvisor-specific;
- it has "Coming soon" rows;
- it does not scan local CLI availability;
- it does not represent Codex or Antigravity as first-class primary agents.

Later, Clawvisor onboarding can consume the global primary agent choice. If the
primary agent is `claude`, use the Claude Code Clawvisor prompt. If it is
`codex` or `antigravity`, route to the future generic/manual Clawvisor flow.

## Proposed Components

### `ZebraAgentKind`

Shared enum for terminal-launchable agents.

Likely location:

```text
Packages/ZebraVault/Sources/ZebraVault/AgentOnboarding/
```

or another ZebraVault-owned directory.

Avoid adding this to upstream cmux models.

### `ZebraAgentInstallScanner`

Pure scanner that returns `[ZebraAgentInstallCandidate]`.

Responsibilities:

- search known binary names;
- search common install paths;
- search `$PATH` when available;
- avoid false positives;
- run bounded version checks;
- return structured candidate state.

It should be unit-testable with an injected environment, similar to
`TerminalDirectoryOpenTarget.DetectionEnvironment` in
`Sources/App/TerminalDirectoryOpenSupport.swift`.

Suggested injected environment:

```swift
struct ZebraAgentScanEnvironment {
    let homeDirectoryPath: String
    let searchPath: String?
    let fileExistsAtPath: (String) -> Bool
    let isExecutableFileAtPath: (String) -> Bool
    let applicationPathForName: (String) -> String?
    let runVersionCommand: (String, [String], TimeInterval) -> VersionCommandResult
}
```

Use injection so tests do not need actual local CLIs.

### `ZebraAgentPreferenceStore`

Typed wrapper around the shared durable preference JSON file.

Responsibilities:

- read saved primary agent;
- validate raw stored values;
- write primary agent;
- read/write surface overrides such as `surfaceOverrides.brainSync`;
- migrate old `UserDefaults` values such as `zebra.brainSync.preferredAgent`;
- clear invalid/deleted preference values if needed.

Preference file:

```text
~/Library/Application Support/zebra/agent/preferences.json
```

Keep this product-level preference separate from onboarding run state.

### `ZebraAgentOnboardingCoordinator`

State machine that turns scan results + saved preference into next action.

Inputs:

- saved primary agent, if any;
- scan results;
- user selection events;
- install completion/failure events.

Outputs:

- auto-selected agent;
- prompt user to select among installed agents;
- prompt user to select an agent to install;
- run installer for selected agent;
- launch selected agent;
- show recoverable failure state.

This coordinator should be testable without SwiftUI.

### `ZebraAgentInstaller`

Runner for provider install flows.

Responsibilities:

- build the provider-specific install command;
- run it in a Zebra terminal;
- re-scan after completion;
- report success/failure to coordinator.

Do not freeze install commands in code without verifying official provider docs
in the implementation session. This plan intentionally does not specify the
exact commands.

### `ZebraAgentLauncher`

Shared launch builder for the selected agent.

Responsibilities:

- build the terminal startup line for each supported agent;
- apply cwd/trust handling;
- include the first-run onboarding prompt;
- later serve ChatPill, brain-sync, and Clawvisor handoffs.

This can be an evolution of `MarkdownChatPillCommand`, or a new lower-level
component that `MarkdownChatPillCommand` delegates to.

## Candidate Discovery Details

### Claude

Candidate binary:

- `claude`

Known complication:

- cmux/Zebra may have an internal Claude wrapper in derived data or app bundle
  paths.
- Existing code has `isCmuxClaudeWrapper(at:)` in
  `CLI/CMUXCLI+ExecutableResolution.swift`.

Scanner should avoid selecting Zebra's own wrapper as the user's installed
Claude Code CLI. Prefer the real user-installed binary.

### Codex

Candidate binary:

- `codex`

No special wrapper issue is known from current code, but scanner should still
prefer executable paths from stable user/system locations over transient build
or app bundle paths.

### Antigravity

Candidate binary:

- `agy`

Official docs install the executable at `~/.local/bin/agy` on macOS/Linux.
If another official binary name appears later, represent it under the same
`ZebraAgentKind.antigravity`.

### Gemini

Do not include in this first-run candidate list.

If a stale `gemini` binary exists on a developer machine, it should not appear
in this onboarding flow.

## Provider CLI Contracts For V1

These contracts are intentionally explicit so a new implementation session can
start without re-litigating the product decisions. Re-check official docs during
implementation if a command fails or the provider docs have changed, but do not
leave installer/launcher behavior unspecified in V1.

### Claude Code

- agent id: `claude`
- display name: `Claude Code`
- binary: `claude`
- preferred macOS/Linux installer:

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

- version probe:

```bash
claude --version
```

- auth probe, advisory only:

```bash
claude auth status
```

- onboarding launch shape:

```bash
cd <cwd> && claude --append-system-prompt <zebra-system-prompt> <zebra-user-prompt>
```

Claude Code documents `claude "query"` as an interactive session with an
initial prompt and `--append-system-prompt` as the per-invocation way to append
custom system instructions. It also documents `claude auth status` as JSON by
default, with exit code 0 when logged in and 1 when not logged in. [Source:
Claude Code installation and CLI reference, 2026-05-29]

### Codex

- agent id: `codex`
- display name: `Codex`
- binary: `codex`
- preferred macOS/Linux installer:

```bash
curl -fsSL https://chatgpt.com/codex/install.sh | sh
```

- version probe:

```bash
codex --version
```

- auth probe:
  - no official noninteractive status command is required for V1;
  - do not implement a Codex status probe in V1; treat auth as `unknown`.

- onboarding launch shape:

```bash
cd <cwd> && codex -C <cwd> <zebra-user-prompt>
```

Codex docs document the standalone installer, `codex` as the terminal command,
first-run sign-in, `--cd` / `-C` for working directory selection, and positional
`PROMPT` as the initial instruction. [Source: OpenAI Codex CLI setup and command
line options, 2026-05-29]

### Antigravity

- agent id: `antigravity`
- display name: `Antigravity`
- binary: `agy`
- preferred macOS/Linux installer:

```bash
curl -fsSL https://antigravity.google/cli/install.sh | bash
```

- expected install path:

```text
~/.local/bin/agy
```

- version probe:

```bash
agy --version
```

- auth probe:
  - no separate status command is required for V1;
  - the CLI attempts local secure-keyring auth and falls back to browser Google
    Sign-In when no saved session exists.

- onboarding launch shape:

```bash
cd <cwd> && agy -p <zebra-user-prompt> --cwd <cwd>
```

Antigravity docs document the macOS/Linux installer, the `agy` binary, keyring
or browser sign-in fallback, and `agy -p "..." --cwd $(pwd)` as a prompt+cwd CLI
usage pattern. [Source: Google Antigravity CLI install/auth and best practices,
2026-05-29]

### Installer Safety

- Installer commands should run only after explicit user selection in the
  Zebra terminal flow.
- The script must show the command label before execution and record
  `install_started` / `install_succeeded` / `install_failed`.
- If an installer exits non-zero, keep the user in the flow with retry,
  choose another agent, and manual instructions fallback.
- Do not run provider installers silently at app startup.

## V1 UX Route

### UI-first default selection with terminal fallback

Default-agent management should not open a Zebra agent terminal as the first
step when Zebra can already make the change locally. The app should show the
supported agents with current CLI install state, then route each click based on
that state:

- installed CLI -> persist `preferences.primaryAgent` immediately in native UI;
- missing CLI -> open a Zebra agent terminal for install/rescan/launch;
- broken CLI -> open a Zebra agent terminal for repair/reinstall;
- installed CLI but native save/scan fails -> open the same terminal fallback
  for that selected agent.

The Zebra terminal remains the canonical recovery and installer surface because
provider installers and first-run login/signup are still interactive terminal
flows. It is no longer the default selection UI for agents that are already
installed and locally selectable.

The terminal flow should still use a static Zebra-owned onboarding script plus
JSON state/log files, not an opaque generated shell blob. Keep
coordinator/scanner independent so first-run onboarding and future settings UI
can share the same state decisions.

[Source: Han/Codex planning conversation, 2026-05-29]

## State Machine Sketch

```text
start
  |
  v
scanAgents
  |
  +-- saved primary found and installed ----> persist/confirm -> launchPrimary
  |
  +-- saved primary found but missing ------> primaryMissing
  |                                             |
  |                                             +-- reinstall saved -> install -> rescan
  |                                             +-- choose installed -> persist -> launch
  |                                             +-- choose different install -> install -> rescan
  |
  +-- no saved primary, 1 installed --------> persist installed -> launchPrimary
  |
  +-- no saved primary, many installed -----> choosePrimary -> persist -> launchPrimary
  |
  +-- no saved primary, none installed -----> chooseAgentToInstall -> install -> rescan
```

Install failure branch:

```text
install -> failed
  |
  +-- retry same install
  +-- choose different agent
  +-- show manual fallback
```

Launch/auth branch:

```text
launchPrimary
  |
  +-- CLI already authenticated -> agent starts normally
  +-- CLI not authenticated ----> provider login/signup flow
  +-- user has no account ------> provider signup flow
```

Zebra does not need to distinguish the last two branches before launch.

## Static Script State Contract

V1 should use a static Zebra-owned script command, referred to here as
`zebra-agent-onboarding`. The app opens a Zebra terminal and runs that script.
The script owns the terminal prompts, install/retry choices, re-scan loop,
selected-agent launch, and ready marker subcommand.

The script should persist two files under Zebra application support:

```text
~/Library/Application Support/zebra/onboarding/agent-cli-state.json
~/Library/Application Support/zebra/onboarding/agent-cli-events.jsonl
```

`agent-cli-state.json` is the current resumable snapshot. Writes must be atomic
(`*.tmp.<pid>` then rename). It should not contain duplicated "last install" or
"last launch" history; completed operations belong in the event log.

Final state shape:

```json
{
  "schemaVersion": 1,
  "runId": "2026-05-29T12-34-56Z-a1b2",
  "phase": "scan",
  "updatedAt": "2026-05-29T12:34:56Z",
  "savedPrimary": "codex",
  "selectedAgent": null,
  "candidates": [
    {
      "id": "codex",
      "displayName": "Codex",
      "binaryName": "codex",
      "executablePath": "/opt/homebrew/bin/codex",
      "version": "0.42.0",
      "installState": "installed",
      "authState": "unknown",
      "terminalLaunchable": true,
      "recommendedAction": "launch"
    }
  ],
  "error": null
}
```

Allowed `phase` values:

```text
scan
choose_primary
choose_install_target
primary_missing
installing
rescanning_after_install
launching_agent
agent_working
waiting_for_continue
complete
failed
```

`selectedAgent` is the current chosen agent for this run. `savedPrimary` is the
persisted `preferences.primaryAgent` value observed at scan start, if any.
`error` is either `null` or a small recoverable error object:

```json
{
  "code": "install_failed",
  "agent": "codex",
  "message": "Installer exited 1",
  "recoverable": true
}
```

Do not add a separate `activeOperation`, `lastInstall`, or `lastLaunch` field in
V1. Those duplicate `phase` plus event-log data. For example,
`phase = "installing"` and `selectedAgent = "codex"` already identify the active
operation, while the exact command label, start time, exit code, and outcome are
append-only events.

`agent-cli-events.jsonl` is append-only and records operation history:

```jsonl
{"ts":"2026-05-29T12:34:56Z","runId":"2026-05-29T12-34-56Z-a1b2","event":"agent_scan_started"}
{"ts":"2026-05-29T12:34:57Z","runId":"2026-05-29T12-34-56Z-a1b2","event":"agent_scan_completed","installed":["codex"],"missing":["claude","antigravity"]}
{"ts":"2026-05-29T12:34:58Z","runId":"2026-05-29T12-34-56Z-a1b2","event":"primary_agent_selected","agent":"codex","selectionMode":"auto_one_installed"}
{"ts":"2026-05-29T12:35:00Z","runId":"2026-05-29T12-34-56Z-a1b2","event":"agent_launch_started","agent":"codex","commandLabel":"codex onboarding prompt"}
{"ts":"2026-05-29T12:40:00Z","runId":"2026-05-29T12-34-56Z-a1b2","event":"agent_ready_reported","agent":"codex","source":"mark-ready"}
{"ts":"2026-05-29T12:40:01Z","runId":"2026-05-29T12-34-56Z-a1b2","event":"agent_onboarding_completed","agent":"codex"}
```

Core event names:

- `agent_scan_started`
- `agent_scan_completed`
- `primary_agent_selected`
- `install_started`
- `install_succeeded`
- `install_failed`
- `agent_launch_started`
- `agent_process_exited`
- `agent_ready_reported`
- `manual_continue_selected`
- `agent_onboarding_completed`
- `agent_onboarding_failed`

Ready/completion contract:

- Zebra launches the selected CLI with a Zebra onboarding prompt.
- That prompt tells the agent what setup work to do and asks it to run
  `zebra-agent-onboarding mark-ready --agent <agent> --run-id <runId>` when
  finished.
- `mark-ready` is the only supported write path for agent-reported completion.
  It validates the current run, appends `agent_ready_reported`, and atomically
  updates `agent-cli-state.json` to `phase = "complete"`.
- The agent must not edit `agent-cli-state.json` directly.
- Do not create a separate `agent-ready.json` marker file in V1. The existing
  state file plus JSONL event log are the canonical channel. A separate marker
  file would create split-brain states such as "state incomplete, marker
  present".

If the selected CLI exits and no `agent_ready_reported` event exists for the
current run, the script should move to `waiting_for_continue` and offer:

- relaunch the same agent with the same onboarding prompt;
- mark complete manually;
- choose another agent.

Auth/status policy:

- Official noninteractive status commands are allowed as advisory probes with a
  short timeout.
- Status probe results may update `authState` or append an advisory event, but
  must not be the completion criterion.
- Completion is based on `mark-ready` or an explicit manual continue choice.
- Do not parse provider token files, inspect Keychain credential internals, call
  provider account APIs, or treat subscription/account eligibility as Zebra's
  responsibility in V1.

Claude Code documents `claude auth status` as a JSON-capable status command
with exit code 0 when logged in and 1 when not logged in. Codex and Antigravity
V1 do not require a separate auth status probe; both should let the provider
CLI own first-run sign-in. [Source: Claude Code CLI reference, OpenAI Codex
CLI/auth docs, Google Antigravity CLI install/auth docs, 2026-05-29]

## Agent Preference Contract

`agent-cli-state.json` is only the resumable snapshot for the current
onboarding run. It must not become the durable product preference store.
Selections that should survive onboarding, app restarts, and future entrypoints
belong in a separate preference file:

```text
~/Library/Application Support/zebra/agent/preferences.json
```

Suggested shape:

```json
{
  "schemaVersion": 1,
  "primaryAgent": "codex",
  "updatedAt": "2026-05-29T12:40:01Z",
  "updatedBy": "onboarding",
  "surfaceOverrides": {
    "brainSync": "claude"
  }
}
```

Resolution rule:

```text
default agent for normal Zebra launches = preferences.primaryAgent
BrainSync recovery agent = preferences.surfaceOverrides.brainSync ?? preferences.primaryAgent
```

Use JSON instead of `UserDefaults` for this shared preference because the
terminal-first onboarding script and the Swift app both need to read/write the
same setting, and tagged Debug / Release / Zebra-branded builds should not
accidentally diverge through bundle-id-specific defaults domains.

BrainSync currently has an agent picker in its failure tooltip and stores
`zebra.brainSync.preferredAgent` in `UserDefaults`. Migrate that value into
`surfaceOverrides.brainSync`, then use `preferences.json` as the long-term
source of truth. When the BrainSync picker changes, update only
`surfaceOverrides.brainSync`; do not change `primaryAgent`.

Preference changes should append audit/debug events, either to
`agent-cli-events.jsonl` in V1 or a future agent preference event log:

```jsonl
{"ts":"2026-05-29T12:50:00Z","event":"primary_agent_changed","from":"codex","to":"antigravity","source":"choose-primary"}
{"ts":"2026-05-29T12:52:00Z","event":"surface_agent_override_changed","surface":"brainSync","from":null,"to":"claude","source":"brainSyncPicker"}
```

[Source: Han/Codex planning conversation, 2026-05-29]

## User-Facing Copy Principles

When no CLI is installed:

- say Zebra needs a local agent CLI to continue;
- ask which agent to install;
- make clear Zebra will run the installer in this terminal.

When multiple CLIs are installed:

- ask which one Zebra should use by default;
- mention this can be changed later if settings exist by then.

When launching a CLI:

- say the provider may ask the user to sign in or create an account;
- do not imply Zebra can verify or create the account itself.

When install fails:

- show the failing provider/tool name;
- show retry/change-agent/manual fallback actions;
- avoid dumping a long shell trace unless the user opens details.

## Follow-On Integration Points

### ChatPill

ChatPill currently defaults to `.codex` in `MarkdownChatPill`.

After shared agent preferences exist:

- default ChatPill selected agent should come from
  `preferences.primaryAgent`;
- if the saved agent is missing, gracefully fall back to the scanner's best
  installed candidate or ask the user.

The existing ChatPill agent picker UI (the dropdown shown from the pill chip)
should not treat every agent click as a global default change. That would make
temporary provider outages, quota issues, or one-off task preferences mutate the
user's durable `primaryAgent`.

Recommended picker behavior:

```text
Agent: Codex ▾

Claude Code      Use for this prompt
Codex        ✓   Default
Antigravity      Use for this prompt
────────────
Manage default agent...
```

- selecting an installed non-default agent from the ChatPill picker launches
  that single prompt with the chosen agent and does not write
  `preferences.primaryAgent`;
- selecting the current default is just the normal default path;
- `Manage default agent...` is the explicit entrypoint for durable default
  changes;
- `Manage default agent` should open native UI that shows all supported agents
  with installed/missing/repair status;
- if the requested default agent is installed, the UI updates
  `preferences.primaryAgent` immediately and does not open a terminal;
- if it is missing or broken, the UI opens the Zebra terminal with the selected
  agent prefilled, runs install/rescan, and only updates
  `preferences.primaryAgent` after the selected CLI is found;
- if the installed-agent immediate update fails, the same selected-agent
  terminal fallback should open.

This keeps one-shot ChatPill routing separate from the durable product default
while still giving the user a nearby "click to change default" path. [Source:
Han/Codex planning conversation, ChatPill picker screenshot, 2026-05-29]

### Brain sync recovery

Brain sync currently has its own failure-tooltip agent picker. It should move
from `UserDefaults` key `zebra.brainSync.preferredAgent` to the shared durable
agent preference JSON:

```text
agent = preferences.surfaceOverrides.brainSync ?? preferences.primaryAgent
```

The existing BrainSync-specific value should migrate into
`surfaceOverrides.brainSync`. This preserves the user's BrainSync choice without
creating a separate long-term source of truth.

### Clawvisor onboarding

Current Clawvisor flow only supports Claude Code. After primary-agent onboarding:

- if primary is Claude, existing Claude Code Clawvisor flow can run;
- if primary is Codex or Antigravity, route to a generic/manual Clawvisor
  setup flow until provider-specific prompts are implemented;
- avoid showing "Claude Code" as the only enabled option when the user has
  chosen another primary agent.

### First-run gbrain onboarding

This task is separate from gbrain install/vault/profile onboarding, but the
agent selection should happen early enough that any later gbrain setup help can
use the selected agent.

Potential ordering:

```text
agent primary setup
-> gbrain install/vault/profile setup
-> source ingestion setup
-> email/Clawvisor setup
```

## Testing Plan

Unit tests should cover the coordinator and scanner without relying on local
developer machine state.

Scanner tests:

- no binaries found;
- only Claude found;
- only Codex found;
- only Antigravity found;
- multiple found;
- stale Gemini binary ignored;
- Claude wrapper path ignored;
- version command timeout returns installed-with-unknown-version or broken,
  depending on chosen semantics;
- non-executable file ignored.

Coordinator tests:

- saved primary installed -> launch without prompt;
- saved primary missing and other candidate installed -> ask before switching;
- no saved primary + one installed -> auto-persist;
- no saved primary + many installed -> ask;
- no saved primary + none installed -> ask install target;
- install success -> rescan -> persist -> launch;
- install failure -> retry/change/manual actions.

Preference tests:

- valid saved raw value read;
- invalid raw value ignored/cleared;
- write primary agent;
- old brain-sync preference migrates into `surfaceOverrides.brainSync`;
- BrainSync resolves override first, then global primary.

Launch tests:

- per-agent startup line includes cwd;
- quoted prompts survive spaces and quotes;
- Claude trust handling does not target wrapper;
- Antigravity invocation uses `agy -p <prompt> --cwd <cwd>`.

Script/state tests:

- state writes are atomic and preserve unknown future fields when practical;
- `mark-ready` rejects a mismatched `runId`;
- `mark-ready` appends `agent_ready_reported` and sets `phase = complete`;
- agent process exit without ready event moves to `waiting_for_continue`;
- manual continue appends `manual_continue_selected` and completes;
- event log remains append-only across retry/relaunch cycles.

## Implementation Notes

- Keep new Zebra-only logic under `Packages/ZebraVault/**` unless it must talk
  directly to cmux `Workspace`, `TabManager`, or pane APIs. Adapter code that
  must touch cmux models belongs under `Sources/Zebra/**`.
- Do not add zebra-only fields to upstream cmux models.
- Do not edit upstream cmux files unless there is no existing Zebra seam and
  the touchpoint is documented.
- Provider install and launch commands are specified in
  `Provider CLI Contracts For V1`. Re-check official docs during
  implementation if a provider command fails or appears stale.
- Treat provider login/signup as an interactive terminal/browser handoff.
- Do not deep-inspect provider token stores in V1. Official status commands are
  allowed only as advisory probes with a short timeout, not as hard gates.
- Avoid using `gemini` in any new first-run candidate logic.
- The selected agent should be launched with an onboarding prompt that includes
  the ready contract: run `zebra-agent-onboarding mark-ready --agent <agent>
  --run-id <runId>` after the Zebra setup work is done.

## Implementation Targets

Default new Swift code location:

```text
Packages/ZebraVault/Sources/ZebraVault/AgentOnboarding/
```

Suggested files:

```text
ZebraAgentKind.swift
ZebraAgentScanModels.swift
ZebraAgentInstallScanner.swift
ZebraAgentPreferenceStore.swift
ZebraAgentOnboardingCoordinator.swift
ZebraAgentLaunchCommand.swift
```

Unit tests:

```text
Packages/ZebraVault/Tests/ZebraVaultTests/ZebraAgentInstallScannerTests.swift
Packages/ZebraVault/Tests/ZebraVaultTests/ZebraAgentPreferenceStoreTests.swift
Packages/ZebraVault/Tests/ZebraVaultTests/ZebraAgentOnboardingCoordinatorTests.swift
Packages/ZebraVault/Tests/ZebraVaultTests/ZebraAgentLaunchCommandTests.swift
```

Static onboarding script:

```text
Resources/zebra-agent-onboarding
```

Use the existing `Resources/zebra-brain-sync` pattern:

- executable bash script;
- bundled as an app resource in `cmux.xcodeproj`;
- resolved from Swift with `Bundle.main.url(forResource: "zebra-agent-onboarding", withExtension: nil)`;
- added to `docs/upstream-touchpoints.md` and `docs/upstream-touchpoints.txt`
  as a Zebra-owned bundled script touchpoint.

Only put adapter code under `Sources/Zebra/**` when it must touch cmux
`Workspace`, `TabManager`, pane APIs, or bundled-resource launching. Do not add
Zebra-only state to upstream cmux models.

## Final Decisions

Decided:

1. V1 default-agent management is UI-first for installed CLIs and opens the
   Zebra terminal only for missing, broken, or failed native selections. The
   fallback terminal uses the same static Zebra-owned onboarding script plus
   JSON state/log files.
2. Ready/completion is reported through
   `zebra-agent-onboarding mark-ready`, which writes the canonical state/log.
   No separate marker file in V1.
3. Provider auth status checks are advisory only. They are not the completion
   criterion.
4. Durable primary-agent preference lives in
   `~/Library/Application Support/zebra/agent/preferences.json`, separate from
   onboarding run state.
5. BrainSync uses `surfaceOverrides.brainSync ?? primaryAgent` from that shared
   preference file. Its current `zebra.brainSync.preferredAgent` value migrates
   into the override field.
6. Antigravity is in scope for V1 actual install/launch support, not just an
   enum placeholder.
7. ChatPill picker agent clicks are one-shot prompt routing. Durable default
   changes happen only through an explicit `Manage default agent` entrypoint.
   Installed agents are saved immediately in UI; missing/broken agents open
   `zebra-agent-onboarding choose-primary --agent <agent>`.
8. V1 should not touch command palette. `Manage default agent...` lives in the
   ChatPill picker only for the first implementation.

## Implementation Checklist

Build the smallest version that proves the product loop:

1. Add `ZebraAgentKind` with `claude`, `codex`, `antigravity`.
2. Add scanner with injected environment and unit tests.
3. Add durable agent preference JSON with `primaryAgent` and
   `surfaceOverrides`.
4. Add coordinator tests for the scenario matrix above.
5. Add the static `zebra-agent-onboarding` script with state/log helpers:
   - atomic `agent-cli-state.json` writes;
   - append-only `agent-cli-events.jsonl`;
   - `mark-ready --agent <agent> --run-id <runId>`.
6. Wire first-run terminal flow:
   - 0 installed -> ask install target;
   - 1 installed -> auto-select;
   - many installed -> ask primary.
7. Implement provider installer/launcher functions from
   `Provider CLI Contracts For V1`.
8. Launch selected CLI with a generic Zebra onboarding prompt that includes the
   `mark-ready` completion contract.
9. If the selected CLI exits without `agent_ready_reported`, offer relaunch,
   manual continue, or choose another agent.
10. Update ChatPill picker behavior:
   - picker agent rows are one-shot prompt routing;
   - add `Manage default agent`;
   - installed durable changes are saved in native UI;
   - missing/broken durable changes go through
     `zebra-agent-onboarding choose-primary --agent <agent>`.
11. Only after this works, connect ChatPill / brain-sync / Clawvisor defaults to
   the shared agent preference file.
