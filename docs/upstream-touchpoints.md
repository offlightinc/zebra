# Upstream Touchpoints

This document lists every cmux (`upstream/main`) file that Zebra is allowed to
modify, and the reason. Any other cmux file change in a Zebra PR is a
**regression** of the adapter separation we did in Phase 1 / Phase 2 of the
[zebra-upstream isolation design](https://github.com/offlightinc/b-brain/blob/main/docs/designs/zebra-upstream-isolation.md).

The companion script `scripts/check-upstream-touchpoints.sh` reads the
machine-readable allowlist in `docs/upstream-touchpoints.txt`.

`./scripts/setup.sh` wires `git config core.hooksPath .githooks`, so the
shared `.githooks/pre-commit` runs the guard on every `git commit`. Bypass
once with `git commit --no-verify`.

## How Zebra is allowed to touch a cmux file

Each touchpoint should fit one of these seam types — `Sources/Zebra/` provides
the implementation, the cmux file only exposes the slot:

| Seam | Where it lives | What cmux contributes |
|---|---|---|
| EnvironmentKey | `Sources/Zebra/.../*` | A `@Environment(\.zebraThing)` read + default value |
| Composer / slot factory | `Sources/Zebra/Sidebar/SidebarComposer.swift`, `Sources/Zebra/Panels/MarkdownPanelViewFactory.swift` | An env value lookup + `factory(context)` call |
| Side-car controller | `Sources/Zebra/Panels/MarkdownPanelController.swift` | A `Notification.Name` declaration + one-line post |
| DI container | `Sources/Zebra/Environment/ZebraServices.swift` | `.injectIntoEnvironment(...)` call in app entrypoint |
| Protocol seam (ZebraVault) | `Sources/Zebra/Adapters/MarkdownPanel+ZebraVault.swift` | A conformance of a cmux model (e.g. `extension MarkdownPanel: ZebraMarkdownPanelModel`) to a public protocol declared inside the `ZebraVault` SPM package. |
| Localization | `Resources/Localizable.xcstrings` zebra-append block | n/a — single file by SwiftUI's table model |
| Project plumbing | `cmux.xcodeproj/project.pbxproj`, `cmuxTests/FileDropOverlayViewTests.swift` | The local-package reference to `Packages/ZebraVault` + the 10 cmux-side adapter file entries under `Sources/Zebra/`. Most Zebra view code now lives inside `Packages/ZebraVault/Sources/ZebraVault/` and has no pbxproj entries at all. |

## Allowed touchpoints

| File | Seam | Reason |
|---|---|---|
| `Sources/AppDelegate.swift` | DI container + first automatic welcome command seam + telemetry wrapper callsite | `ZebraServices.makeDefault(tabManager: tabManager).injectIntoEnvironment(...)` wraps the root `ContentView` once per `createMainWindow` and lets Zebra-owned socket bridges route by window-local `TabManager`. The first automatic welcome terminal runs Zebra's `zebra-agent-onboarding` script when the Zebra agent onboarding JSON says it is still needed; the manual Welcome menu keeps upstream `cmux welcome`. PostHog lifecycle callsites route to Zebra-owned `ZebraPostHogAnalytics` so upstream `PostHogAnalytics.swift` stays untouched. |
| `Sources/cmuxApp.swift` | Zebra default registration + settings slot | Wraps settings-file bootstrap with `ZebraAppearanceDefaults.prepareLaunchSeed()` / `finishLaunchSeed(...)` so Zebra first-launch defaults can diverge from upstream without changing `AppearanceSettings.defaultMode`. It also exposes one upstream-neutral `SettingsAppSectionExtensionSlot`; Zebra installs the Chat Pill pane-placement row from `Sources/Zebra/Environment/ZebraServices.swift`. |
| `Sources/ContentView.swift` | Composer slot + env key + `import ZebraVault` | Builds `SidebarSlots(workspaceList: …, defaultFooter: …, onSendFeedback: …)` and calls `sidebarComposer.compose(slots)`. Reads `\.sidebarExtraLeadingInset` for fullscreen control padding. Imports `ZebraVault` to spell `VerticalTabsSidebarVaultState` for the `@EnvironmentObject` declaration. `commandPaletteSurfaceKindLabel` / `commandPaletteSurfaceKeywords` carry the `PanelType.email` branches ("Email" + email/mail/gmail/inbox/thread keywords). |
| `Sources/Panels/PanelContentView.swift` | View factory | `\.markdownPanelViewFactory` env lookup + generic `\.customPanelViewFactory` seam (`(CustomPanelViewContext) -> AnyView?`). Cmux common code does not name any Zebra concrete panel type — `panel.panelType == .email` routes to `customPanelViewFactory`, which is registered by `ZebraServices` and performs its own `panel as? ZebraEmailThreadPanel` cast inside the Zebra module. |
| `Sources/Panels/MarkdownPanelFileLinkResolver.swift` | Markdown source link resolver | Resolves extensionless brain-style source paths such as `sources/foo` to nearby markdown files (`.md`, `.markdown`, `.mkd`, `.mdx`) or directory `README.md` / `index.md`, so compact source icons can open local brain source documents. |
| `Sources/Panels/MarkdownPanelView.swift` | Markdown renderer inset plumbing | Passes a bottom-content inset into `MarkdownWebRenderer` so source-icon rendering can share the web renderer while preserving panel bottom padding. |
| `Sources/Panels/MarkdownWebRenderer.swift` | Markdown renderer bridge | Hosts the web markdown renderer for both cmux markdown panels and Zebra markdown panels, including click-through from compact source icons to local markdown candidates. |
| `Sources/Panels/Panel.swift` | First-class panel kind | `PanelType.email` case. Zebra-owned panel kind; rendering goes through `customPanelViewFactory` so cmux exhaustive switches stay total without naming any Zebra type. |
| `Sources/Workspace.swift` | First-class surface kind + exhaustive switch coverage | `SurfaceKind.email` constant + `.email` branches in `surfaceKind(for:)`, the session-snapshot builder, and `createPanel(from:inPane:)`. Session restore deliberately drops the `.email` branch (email panels re-open from the sidebar, not from serialized state). |
| `Sources/CmuxLifecycleEventPublishing.swift` | Exhaustive switch coverage | `cmuxEventSurfaceKind` returns `"email"` for `PanelType.email`. |
| `Sources/TerminalPaneDropTargetView.swift` | Exhaustive switch coverage | Pane drop dispatch returns `nil` for `PanelType.email` (email panel is not a terminal/editor drop target). |
| `Sources/Search/GlobalSearchDocuments.swift` | Exhaustive switch coverage | `browseHit` maps `PanelType.email` to `GlobalSearchKind.title` — email panels surface in global search through their tab title only. |
| `Sources/TerminalController.swift` | V2 socket dispatch seam | Registers `zebra.email_draft.*` methods in the existing socket/RPC dispatcher and forwards implementation to `ZebraEmailDraftSocketBridge` in Zebra-owned code. Only `zebra.email_draft.focus` is focus-intent; list/create/update run through the socket worker without app activation. |
| `Sources/Panels/MarkdownPanel.swift` | Side-car cleanup + `import ZebraVault` | `static let didCloseNotification` + `NotificationCenter.default.post(...)` in `close()`. `updateFrontmatter(key:value:)` stays because it has to mutate `@Published private(set) var content` and calls `BrainFrontmatterWriter.setScalar` (which now lives in ZebraVault). |
| `Sources/WorkspaceContentView.swift` | View factory plumbing | Passes `workspace:` to `PanelContentView` so the markdown view factory can pull `Workspace`-bound helpers out of the context. |
| `Sources/SessionPersistence.swift` | Preference override (TODO migrate) | `defaultSidebarWidth: 300` (vs upstream `200`) — Zebra ships a wider rail-aware sidebar by default. Single constant; eventually move to a `\.zebraDefaultSidebarWidth` env value during a future Phase 1.4 finish-up. |
| `Sources/WindowChromeMetrics.swift` | Upstream drift only | Awaits next rebase. `SidebarWorkspaceListMetrics.secondRowHeight` is no longer consumed from this file by Zebra; Phase 3.3 introduced a `ZebraSidebarMetrics.firstRowTopOffset = 30` hard-coded mirror inside ZebraVault. |
| `Sources/WindowDragHandleView.swift` | Preference override (TODO migrate) | `MinimalModeSidebarTitlebarControlsMetrics.leadingInset` adds `VerticalTabsSidebarModeRail.fixedWidth`. Same `\.sidebarExtraLeadingInset` pattern Phase 1.2 used for fullscreen controls would cover this; pending a verification pass that the minimal-mode and fullscreen geometries match. |
| `Resources/Localizable.xcstrings` | Localization | Zebra-only keys appended after upstream's last entry. The upstream block stays byte-identical (one historical override on `settings.app.openMarkdownInCmuxViewer.subtitle`). **Never** split into a second `.xcstrings` — SwiftUI compiles it into a separate string table and `String(localized:)` without `table:` won't find it (Phase 1.3 regression learning). |
| `Resources/markdown-viewer/shell.html` | Markdown renderer UX | Collapses `[Source: ...]` citation text into one compact source icon, preserves the original source text for hover/export, and routes clicks to supported URLs or markdown source files. |
| `Resources/zebra-brain-sync` | Zebra-owned bundled script | Zebra's app-managed brain sync subprocess. It validates markdown brain repo changes, auto-commits them with a Slack-readable `Slack-Summary` / `Changed items` / `Details` commit body, rebases, pushes, and optionally pings the GBrain remote. |
| `Resources/zebra-agent-onboarding` | Zebra-owned bundled script | Zebra's terminal-first primary-agent onboarding command. It scans supported agent CLIs, manages installer/launch prompts, persists onboarding state/events, and verifies completion with provider readiness probes. |
| `Sources/Auth/AuthEnvironment.swift` | Auth tenant constants | `developmentStackProjectID` + `developmentStackPublishableClientKey` are Zebra-owned. Sign-in flows land users in Zebra's Stack Auth project rather than cmux's. The cmux env-var seam (`CMUX_STACK_PROJECT_ID`, `CMUX_STACK_PUBLISHABLE_CLIENT_KEY`) is the right long-term mechanism, but until `reload.sh`-side `LSEnvironment` injection lands (also upstream-owned), the dev constants are overridden in-place. |
| `cmuxTests/FileDropOverlayViewTests.swift` | DI container in tests | `ZebraServices.makeDefault().injectIntoEnvironment(ContentView().zebraStoreBindings()...)` mirrors the prod entrypoint. |
| `cmuxTests/MarkdownPanelTests.swift` | Lifecycle test for Zebra-owned MarkdownPanel behavior | Drives `MarkdownPanel.close()` + `Workspace.closePanel` + `Workspace.openOrFocusMarkdownContent` to verify `MarkdownPanelControllerRegistry` releases controllers on close and that a reopened panel starts fresh at `.defaultShown`. Lives under `cmuxTests/` because the lifecycle spans cmux types (`Workspace`, `TabManager`); the controller/registry under test are Zebra-owned. |
| `cmuxTests/SessionPersistenceTests.swift` | Markdown resolver behavior tests | Covers observable `MarkdownPanelFileLinkResolver` behavior for extensionless brain-style source paths and directory README fallback. |
| `cmuxTests/GhosttyConfigTests.swift` | Zebra analytics helper tests | Covers `ZebraPostHogAnalytics` property shaping, privacy guards, flush policy, and split sidebar event taxonomy. Lives in `cmuxTests/` because the analytics bridge is a Zebra-owned app module file outside the `ZebraVault` package. |
| `cmuxTests/ZebraEmailArchiveTabCloseTests.swift` | Zebra email archive tab-close tests | Verifies `Workspace.closeEmailThreadPanels(threadId:)` closes the archived thread's tab (and only that tab) after archive succeeds. Lives in `cmuxTests/` because the behavior spans cmux `Workspace`/Bonsplit types; the panel and archive flow are Zebra-owned. |
| `cmuxTests/MarkdownSidebarOpeningTests.swift` | Zebra workspace integration tests | Covers Chat Pill companion-pane placement/reuse and keeps Zebra sidebar content out of registry-marked agent panes. Lives in `cmuxTests/` because the behavior spans cmux `Workspace`/Bonsplit types and ZebraVault placement policy. |
| `cmux.xcodeproj/project.pbxproj` | Project plumbing | `XCLocalSwiftPackageReference "ZebraVault"` + the 10 surviving cmux-side adapter file entries under `Sources/Zebra/`. After Phase 3, ~200 Zebra-related entries no longer live in pbxproj. Don't touch any other group / target. |
| `CLAUDE.md` | Docs | The "Zebra ↔ cmux 분리 원칙" section. |
| `docs/upstream-touchpoints.md` / `docs/upstream-touchpoints.txt` | Docs / lint | This file and the guard list. |

## Disallowed (with examples that have come up)

- **New `@EnvironmentObject` for a Zebra store on a cmux struct.** Read via `@Environment(\.zebra)?.foo` if you need ephemeral access; otherwise attach `.zebraStoreBindings()` once at the root and consume the store inside the Zebra view.
- **New stored fields on `MarkdownPanel` (or any other cmux model) that only matter for Zebra workflows.** Put them on a side-car controller owned by `ZebraServices`. Hard constraints documented in `Sources/Zebra/Panels/MarkdownPanelController.swift`.
- **Adding `import Bonsplit` to a cmux file outside the existing seams.** `import ZebraVault` is allowed in a small set of allow-listed cmux files (currently `AppDelegate`, `ContentView`, `Sources/Panels/MarkdownPanel.swift`) when the file genuinely needs to name a Zebra public type. Any other Zebra-only module import means the seam is missing or being bypassed.
- **Inline reformatting `Resources/Localizable.xcstrings`'s upstream block.** That nukes the byte-identical guarantee and turns every upstream string PR into a merge conflict.

## What to do if you need a new touchpoint

1. Add the seam to the cmux file (env key / factory / slot / notification — whichever fits).
2. Implement the Zebra side under `Sources/Zebra/**`.
3. Add the cmux file to `docs/upstream-touchpoints.txt` with a comment explaining the seam.
4. Update the table above.
