# Zebra Agent Terminal Placement Handoff

## Current status

This document is the handoff record for the agent-terminal placement work on
`codex/zebra-agent-terminal-placement`.

The original handoff in `/Users/han/zebra-phase3` was written before the final
implementation decisions. The current implementation intentionally differs in a
few important ways:

- Agent terminal creation is centralized in one shared launcher,
  `Workspace.openZebraAgentTerminal(...)`.
- The launcher supports exactly two placement anchors:
  `contentAnchored(contentPanelId:contentPaneId:)` for Chat Pill and
  `focusAnchored` for standalone agent entrypoints.
- Source-specific `companionId` / `companionPaneId` state was removed.
  Companion reuse is now derived from current layout plus
  `ZebraAgentTerminalRegistry`.
- The old score-based content placement resolver was removed. Content open now
  follows deterministic pane rules.
- The registry remains runtime-only and resets when the app process restarts.

See also:

- `docs/zebra-pane-placement-policy.md`
- `Packages/ZebraVault/Sources/ZebraVault/AgentTerminal/ZebraAgentTerminalRegistry.swift`
- `Sources/Zebra/Adapters/MarkdownPanel+ZebraVault.swift`
- `cmuxTests/MarkdownSidebarOpeningTests.swift`

## Problem

Zebra starts with a single default terminal tab in one pane. That pane is
neutral: it is not a content pane and not an agent pane.

The first Zebra action should not create a split just because it is first:

```text
Start:
[Terminal]

Open markdown/email first:
[Terminal + Markdown/Email]

Open standalone agent first:
[Terminal + Agent]
```

The split decision matters on the next opposite action:

```text
Content first, then agent:
[Markdown] [Agent]

Agent first, then content:
[Markdown] [Terminal + Agent]
```

This must work through all Zebra agent entrypoints:

- Markdown Chat Pill
- Email Chat Pill
- Clawvisor onboarding
- Brain sync failure/debug agent

## Why a registry is needed

Content panels are distinguishable by panel type:

```swift
panel is MarkdownPanel
panel is ZebraEmailThreadPanel
panel is FilePreviewPanel
```

Agent terminals are not distinguishable by type. The default terminal, a
manually opened terminal, a Chat Pill terminal, a Clawvisor onboarding terminal,
and a brain-sync debug terminal are all `TerminalPanel`.

These layouts look identical if the code only checks panel types:

```text
[Terminal]
[Terminal + Sync Agent]
```

So Zebra needs a side-car marker saying "this specific terminal panel was opened
by a Zebra agent launcher".

The marker is keyed by terminal panel id, not pane id:

- A pane can hold multiple tabs.
- A user can move a tab to another pane.
- Panel id follows the terminal tab; pane id memory would go stale.
- A normal empty terminal pane should not become an agent pane just because it
  is next to content.

## Registry

`ZebraAgentTerminalRegistry` is a Zebra-owned runtime marker table.

It stores:

- terminal `panelId`
- `source`
  - `.markdownFile(path)`
  - `.emailThread(id)`
  - `.clawvisorOnboarding`
  - `.brainSyncFailure`
- selected `agent`
- `createdAt`

The registry is owned by `ZebraServices.agentTerminals`, not by SwiftUI view
state. That keeps the markers alive across view churn, tab switches, and split
reparenting while the app process is running.

It does not persist to disk. After app restart, the registry is empty again.
That is intentional. Agent pane identity is runtime placement state, not a
document model.

Before each placement query, the workspace prunes the registry against live
`workspace.panels.keys` so closed terminal panel ids do not linger forever.

## Shared launcher

All Zebra agent entrypoints use:

```swift
workspace.openZebraAgentTerminal(
    startupLine: ...,
    source: ...,
    agent: ...,
    anchor: ...,
    markedBy: agentTerminals
)
```

The launcher handles the common work:

1. Prune stale registry entries.
2. Resolve the target pane.
3. Create a terminal tab or split.
4. Mark the new terminal panel id in the registry.
5. Send the startup command when the terminal surface is ready.

This avoids having Chat Pill, Clawvisor onboarding, and brain-sync debug each
carry a slightly different placement policy.

## Placement anchors

### `contentAnchored`

Used by Markdown Chat Pill and Email Chat Pill.

Inputs:

- source content panel id
- source content pane id

Rules:

```text
1. Look to the right of the source content pane.
2. If a registry-marked agent terminal pane is there, add a terminal tab there.
3. Otherwise create a new right split from the source content panel.
4. Mark the new terminal panel id in the registry.
```

Important behavior:

- A normal empty terminal pane on the right is not reused as a Chat Pill
  companion.
- Repeated Chat Pill use from the same markdown/email content pane stacks agent
  terminals into the same registry-marked companion pane.
- The old `companionId` memory is no longer needed because the launcher derives
  companion identity from layout plus registry marks.

### `focusAnchored`

Used by Clawvisor onboarding and Brain sync failure/debug agent.

Inputs:

- current workspace focus only

Rules:

```text
1. If the focused pane already contains a registry-marked agent terminal,
   add a terminal tab there.
2. Else if the focused pane has a registry-marked agent terminal pane to its
   right, add a terminal tab there.
3. Else if the focused pane is terminal-only and unmarked, treat it as neutral
   and add a terminal tab there.
4. Else create a new right split from the focused pane.
5. Fallback: if focus is unavailable but an agent pane exists, add a tab there.
6. Fallback: otherwise split from the first available content candidate.
7. Mark the new terminal panel id in the registry.
```

This preserves the important neutral-terminal case:

```text
Start:
[Terminal]

Open Clawvisor or Brain sync agent:
[Terminal + Agent]
```

But it protects content panes:

```text
Focused content:
[Markdown]

Open Clawvisor or Brain sync agent:
[Markdown] [Agent]
```

## Content open rules

Content open means sidebar markdown/email open, and the email-draft focus path
that opens an email thread from an agent/tool call.

The old score-based resolver is gone. There is no
`scorePaneForContentOpen` policy anymore, and content open does not search for
"best" panes by content kind or anchor score.

The deterministic rule is:

```text
1. If the same target is already open outside an agent companion pane, focus it.

2. Resolve the requested pane.
   Sidebar markdown/email uses:
   focusedPaneId ?? firstPane

3. If the requested pane is not an agent companion pane, use it.

4. If the requested pane is an agent companion pane, use the first non-agent
   pane in layout order.

5. If every pane is an agent companion pane, create a new content split to the
   left of the first available pane.
```

Consequences:

- A normal terminal pane is eligible for content if it is not registry-marked.
- A registry-marked agent pane is excluded from automatic content placement.
- Manual user mixing is not undone. The rule only controls automatic placement.
- If only agent panes exist, content opens as a left split using
  `insertFirst = true`.

Examples:

```text
Start:
[Terminal]

Open markdown:
[Terminal + Markdown]
```

```text
Agent first:
[Terminal + Agent]

Open markdown:
[Markdown] [Terminal + Agent]
```

```text
Content first:
[Markdown]

Open standalone agent:
[Markdown] [Agent]
```

```text
Normal terminal right of content:
[Markdown] [Terminal]

Run Chat Pill from Markdown:
[Markdown] [Terminal] [Agent]

The normal terminal is not auto-promoted to Chat Pill companion.
```

## Entrypoints

### Markdown Chat Pill

File:

- `Sources/Zebra/Panels/ZebraMarkdownPanelView.swift`

Current behavior:

- Builds a markdown source from the panel file path.
- Calls `openZebraAgentTerminal(...)`.
- Uses `.contentAnchored(contentPanelId: panel.id, contentPaneId: paneId)`.
- Uses the shared launcher for terminal creation, registry mark, and startup
  input.

### Email Chat Pill

File:

- `Sources/Zebra/Panels/MarkdownPanelViewFactory.swift`

Current behavior:

- Builds an email-thread source from the thread id.
- Calls `openZebraAgentTerminal(...)`.
- Uses `.contentAnchored(contentPanelId: panel.id, contentPaneId: paneId)`.
- Uses the shared launcher for terminal creation, registry mark, and startup
  input.

### Clawvisor onboarding

File:

- `Sources/Zebra/Sidebar/ZebraSidebarBody.swift`

Current behavior:

- Prepares the Clawvisor onboarding startup command.
- Calls `openZebraAgentTerminal(...)`.
- Uses `source: .clawvisorOnboarding`.
- Uses `.focusAnchored`.

### Brain sync failure/debug agent

File:

- `Sources/Zebra/Sidebar/ZebraSidebarBody.swift`

Current behavior:

- Builds the brain-sync failure context startup command.
- Calls `openZebraAgentTerminal(...)`.
- Uses `source: .brainSyncFailure`.
- Uses `.focusAnchored`.

## Content integration points

Files:

- `Sources/Zebra/Sidebar/ZebraSidebarBody.swift`
- `Sources/Zebra/Adapters/MarkdownPanel+ZebraVault.swift`
- `Sources/Zebra/Environment/ZebraServices.swift`

Current behavior:

- Sidebar markdown/email resolves `requestedPaneId` as:

```swift
workspace.bonsplitController.focusedPaneId
    ?? workspace.bonsplitController.allPaneIds.first
```

- It passes `excludedAgentCompanionPaneIds` from:

```swift
workspace.zebraAgentCompanionPaneIds(markedBy: agentTerminals)
```

- `openMarkdownFromZebraSidebar(...)` and `openEmailThreadFromSidebar(...)`
  apply the deterministic non-agent pane rule.
- Email draft socket focus also excludes registry-marked agent panes when it
  opens a thread.

## Behavior-level tests

Coverage added/updated:

- `Packages/ZebraVault/Tests/ZebraVaultTests/ZebraAgentTerminalRegistryTests.swift`
- `cmuxTests/MarkdownSidebarOpeningTests.swift`

Covered behaviors:

- Registry marks panel ids and prunes stale panel ids.
- Registry can identify the latest agent for a source in a pane.
- Chat Pill reuses only registry-marked right companion panes.
- A normal empty terminal pane on the right is not treated as a Chat Pill
  companion.
- Focus-anchored standalone agents reuse a focused agent pane.
- Focus-anchored standalone agents use a terminal-only neutral pane without
  splitting.
- Focus-anchored standalone agents split right from content panes.
- Content open excludes registry-marked agent panes.
- Normal terminal panes remain non-agent unless marked.
- Content can split left when only agent panes are available.

Manual scenarios still worth checking in a tagged debug app:

1. Fresh launch, open markdown/email first.
   - Expected: content opens in the initial terminal pane, no split.
2. Fresh launch, open Clawvisor or Brain sync agent first.
   - Expected: agent opens in the initial terminal pane, no split.
3. Agent first, then markdown/email.
   - Expected: content opens in a left split.
4. Content first, then Clawvisor or Brain sync agent.
   - Expected: agent opens in a right split.
5. Markdown Chat Pill twice from the same markdown pane.
   - Expected: both terminal tabs stack in the same marked companion pane.
6. Email Chat Pill twice from the same email pane.
   - Expected: both terminal tabs stack in the same marked companion pane.
7. Empty normal terminal pane to the right, then Chat Pill.
   - Expected: Chat Pill creates a new agent split instead of reusing the empty
     normal terminal.

## Non-goals

- Do not introduce `AgentTerminalPanel`.
- Do not remove `final` from `TerminalPanel`.
- Do not add Zebra-only stored properties to cmux panel models.
- Do not persist the registry across app restarts.
- Do not infer that a manually opened terminal is an agent terminal.
- Do not reintroduce pane scoring for content open.
