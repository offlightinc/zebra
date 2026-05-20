# Phase 3 SPM Extraction RFC

Status: **draft**
Branch: `phase3-spm`
Baseline: `ee1c3de98` (Merge upstream/main) + two merge-fixups in this branch:

- `Sources/Zebra/Panels/MarkdownPanelViewFactory.swift` — add `appearance: PanelAppearance` field to `MarkdownPanelViewContext` (upstream `PanelContentView` now passes it).
- `Sources/ContentView.swift` — remove dangling reference to `FirstMouseGatedHostingOverlay()` that was never defined.

Goal: extract `Sources/Zebra/**` (67 Swift files) into `Packages/ZebraVault/` (a local SPM
package), reducing `cmux.xcodeproj/project.pbxproj` Zebra file entries from ~240 → 0 so
upstream merges/rebases no longer collide on pbxproj.

This RFC answers the §3.0 feasibility questions before any extraction.

---

## §1. Upstream symbol access audit

Symbols Zebra touches in actual code (comments excluded), with the cmux-side access
level Zebra would need.

| cmux symbol | Zebra sites | Definition | Access today | Notes |
|---|---|---|---|---|
| `MarkdownPanel` (cmux `final class … : Panel, ObservableObject`) | `ZebraMarkdownPanelView.@ObservedObject panel`; `ActiveMarkdownPathsObserver` cast | `Sources/Panels/MarkdownPanel.swift:15` | `internal` | **Deepest dep.** Zebra reads 7 members and subscribes to `@Published focusFlashToken`. |
| `Workspace` (cmux `final class … : ObservableObject`, 7000+ LOC) | `ZebraMarkdownPanelView.workspace`; `ActiveMarkdownPathsObserver` Combine sink on `objectWillChange` | `Sources/Workspace.swift:7153` | `internal` | Zebra calls 5 methods: `openOrFocusMarkdownSurface`, `newTerminalSurface`, `newTerminalSplit`, `paneId(forPanelId:)`, plus `bonsplitController.allPaneIds`. |
| `TabManager` | `ZebraSidebarBody.@EnvironmentObject`; `ZebraStoreBindings.@EnvironmentObject`; `MarkdownPanelViewFactory.@EnvironmentObject`; `ActiveMarkdownPathsObserver.tabManager` | `Sources/TabManager.swift:774` | `internal` | Reads `tabs`, `selectedTabId`, `$selectedTabId` publisher. |
| `FilePreviewPanel` | `ActiveMarkdownPathsObserver` runtime cast | `Sources/Panels/FilePreviewPanel.swift` | `internal` | Type-check only, no member access. |
| `TerminalPanel` | `ZebraMarkdownPanelView.createAgentTerminalTab() -> TerminalPanel?` (via `workspace.newTerminalSurface` / `newTerminalSplit`) | `Sources/Panels/TerminalPanel.swift` | `internal` | Returned value, used through workspace API only. |
| `SidebarSelectionState` | `ZebraSidebarBody.@EnvironmentObject` | cmux model | `internal` | Sidebar mode rail uses it. |
| `PaneID` | `MarkdownPanelViewContext.paneId`, `ZebraMarkdownPanelView.paneId`, `MarkdownPanelController.chatCompanionPaneId` | `Bonsplit` module | `public` (Bonsplit SPM) | Already a Swift Package — fine to depend on. |
| `Bonsplit` | 3 imports inside `Sources/Zebra/Panels/` | `vendor/bonsplit/Package.swift` | local SPM | `ZebraVault` can list it as `.package(path: "../../vendor/bonsplit")`. |

### Surface area summary — the markdown panel slice (deepest coupling)

```
ZebraMarkdownPanelView reads:
  panel.{isFileUnavailable, focusFlashToken, content, displayTitle, filePath,
         id, updateFrontmatter(key:value:)}
  workspace.{openOrFocusMarkdownSurface(inPane:filePath:),
             newTerminalSurface(...), newTerminalSplit(from:...),
             paneId(forPanelId:), bonsplitController.allPaneIds}

ActiveMarkdownPathsObserver reads:
  tabManager.{tabs, selectedTabId, $selectedTabId publisher}
  workspace.{objectWillChange, bonsplitController.{allPaneIds,
             selectedTab(inPane:)}, panelIdFromSurfaceId(_:), panels[panelId]}
  + runtime type casts: `as? FilePreviewPanel`, `as? MarkdownPanel`
```

### Extraction options

**A. Public-ify cmux internals.** Add `public` to `MarkdownPanel`, `Workspace`,
`TabManager`, each accessed member. Violates the Zebra/cmux split rule
("cmux 파일 직접 수정 금지") at scale. Every upstream change to these models risks
public-modifier conflict at rebase. **Reject.**

**B. Closure delegation everywhere.** Pass closures + value snapshots into Zebra views.
For `ObservableObject` reactivity, forward Publishers as `AnyPublisher<Void, Never>` or
wrap each property in a Zebra-owned `@Published` mirror that cmux updates. Roughly:
rewrite `ZebraMarkdownPanelView` (854 LOC) to take ~12 closures + publishers; rewrite
`ActiveMarkdownPathsObserver` to receive a publisher of `Set<String>` instead of
computing it from the model graph. Significant view-code churn but **zero cmux model
changes**.

**C. Protocol seam (recommended).** Define protocols in `ZebraVault` that the markdown
panel surface requires. cmux declares conformances in new files under
`Sources/Zebra/Adapters/` (Zebra-owned territory by current rules):

```swift
// In ZebraVault:
public protocol ZebraMarkdownPanelModel: ObservableObject {
    var isFileUnavailable: Bool { get }
    var focusFlashToken: Int { get }      // @Published in conformance
    var content: String { get }
    var displayTitle: String { get }
    var filePath: String { get }
    var id: PanelID { get }
    func updateFrontmatter(key: String, value: String)
}

public protocol ZebraMarkdownWorkspace: AnyObject, ObservableObject {
    func openOrFocusMarkdownSurface(inPane: PaneID, filePath: String) -> ...
    func newTerminalSurface(...) -> (any ZebraTerminalPanel)?
    func newTerminalSplit(from: PanelID, ...) -> (any ZebraTerminalPanel)?
    func paneId(forPanelId: PanelID) -> PaneID?
    var allPaneIds: Set<PaneID> { get }   // flattened from bonsplitController
}
```

Then on the cmux side (new file, no upstream-cmux source edits):

```swift
// Sources/Zebra/Adapters/MarkdownPanel+Zebra.swift
extension MarkdownPanel: ZebraMarkdownPanelModel {}
extension Workspace: ZebraMarkdownWorkspace { /* flatten bonsplitController */ }
```

Swift access rules: a public protocol from another module can be conformed to by an
internal type **in the type's defining module** without making the type public. Conformance
is then exposed via the protocol-typed value only, which is what ZebraVault views consume.

This pattern keeps every existing cmux file byte-identical to upstream — only **new**
files appear under `Sources/Zebra/Adapters/`, which is already Zebra territory.

**Recommended: C with B as a fallback** for non-`ObservableObject` utilities (e.g.,
`cmuxAccentColor`) where a protocol is overkill — those become closures on
`ZebraServices`.

---

## §2. App-internal style/utility audit

| Symbol | Sites in Zebra | cmux definition | Strategy |
|---|---|---|---|
| `FocusFlashPattern` (enum, ring metrics + animation segments) | `ZebraMarkdownPanelView` x4 | `Sources/Panels/Panel.swift:203` | **Mirror in ZebraVault.** Read-only constants, no behavior. ~10 LOC. |
| `cmuxMarkdownTheme` | `ZebraMarkdownPanelView` x2 | **local** (private var inside `ZebraMarkdownPanelView`) | No action — definition already inside Zebra. |
| `cmuxDebugLog(_:)` | `ZebraMarkdownPanelView` x2 | `Sources/App/DebugLogging.swift:5` (free fn, `#if DEBUG`) | **Depend on `CMUXDebugLog` SPM** (`Packages/CMUXDebugLog/`). ZebraVault adds `.package(path: "../CMUXDebugLog")`. |
| `cmuxAccentColor()` | `ZebraMarkdownPanelView` x2 | `Sources/Sidebar/SidebarAppearanceSupport.swift:74` | **Closure-inject** via `ZebraServices`: a `() -> Color` accent provider that cmux fills in at services construction. |
| `WindowChromeMetrics` | `Sources/Zebra/Sidebar/ZebraSidebarMetrics.swift` (doc-comment only) | `Sources/WindowChromeMetrics.swift:3` | No code ref. No action needed. |
| `KeyboardShortcut*`, `CmuxConfig*`, `MinimalModeChromeMetrics`, `CMUXUITestCapture`, `sentryBreadcrumb`, `SidebarWorkspaceScrollInsets`, `FirstMouseGatedHostingOverlay` | 0 hits in Zebra | n/a | No action. |

Net new SPM deps for ZebraVault: `CMUXDebugLog`, `Bonsplit`, `MarkdownUI` (§3).
Net mirrors: `FocusFlashPattern` (trivial).
Net closures: `accent: () -> Color` on `ZebraServices`.

---

## §3. MarkdownUI + Bonsplit SPM check

- **MarkdownUI** — remote SPM already wired through xcodeproj:
  - URL: `https://github.com/gonzalezreal/swift-markdown-ui` @ `2.4.1`
  - Registered at `cmux.xcodeproj/project.pbxproj:3050,3111`
  - Reachable from a sub-package by adding the same `.package(url: …, from: "2.4.1")` to
    `Packages/ZebraVault/Package.swift`. SPM dedupes against the workspace.

- **Bonsplit** — local SPM at `vendor/bonsplit/Package.swift`. ZebraVault depends as
  `.package(path: "../../vendor/bonsplit")` (resolve relative path at scaffold time).

- **CMUXDebugLog** — sibling local SPM. `.package(path: "../CMUXDebugLog")`.

No blockers.

---

## §4. Localization strategy decision

- **215** `String(localized:` callsites in `Sources/Zebra/`.
- **190** unique localization keys, all in `Resources/Localizable.xcstrings` (112,588 lines).
- No `BEGIN ZEBRA / END ZEBRA` marker — zebra-only keys are namespace-prefixed
  (`brain.*`, `goals.*`, `task.picker.*`, `email.*`, etc.).

**Option A — Bundle.module catalog in ZebraVault.** Move zebra keys to
`Packages/ZebraVault/Sources/ZebraVault/Resources/Localizable.xcstrings`. Rewrite all 215
sites to `String(localized: "key", defaultValue: "…", bundle: .module)`.

  - Phase 1.3 already tried a variant (separate `Resources/Localizable+Zebra.xcstrings`)
    and **regressed at runtime**: SwiftUI compiles each `.xcstrings` to a separate table,
    and `String(localized:)` only consults the default table without explicit `bundle:`.
  - With explicit `bundle: .module` everywhere this should work, but any missed
    callsite falls back silently to `defaultValue:` — easy regression to ship.

**Option B — keep shared cmux `Localizable.xcstrings`.** Zebra calls stay byte-identical.

  - Pro: zero callsite churn; no Phase-1.3-style regression risk; runtime parity with
    main.
  - Con: cmux xcstrings keeps growing — but 190 keys in a 112k-line file with disjoint
    namespace prefixes adds near-zero upstream merge cost.

**Decision: B.** Phase 3's goal is reducing pbxproj merge surface, not isolating zebra
resources. The xcstrings file is a single file reference in pbxproj — it doesn't move
during extraction. Sharing it does not increase merge cost and sidesteps the runtime trap
already learned. Mark A as a possible post-Phase-3 cleanup.

Operational rule (continues current practice): new zebra strings keep their namespace
prefixes so they're filterable in the shared catalog.

---

## §5. Test target placement

Zebra-related tests in `cmuxTests/`:

| File | LOC | Type | Move to ZebraVaultTests? |
|---|---|---|---|
| `GoalFrontmatterParserTests.swift` | 63 | Pure parser test of `GoalFrontmatterParser` | **Yes** — pure logic, depends only on ZebraVault. |
| `BrainObjectParserGoalStatusTests.swift` | 88 | Pure parser test | **Yes** — same. |
| `FileDropOverlayViewTests.swift` | (large) | Primarily tests cmux `FileDropOverlay` with incidental `BrainObject` refs | **No** — keep in cmuxTests. |

Seed `Packages/ZebraVault/Tests/ZebraVaultTests/` with the two pure-parser tests.
`cmuxTests/` keeps cross-module / integration tests.

---

## Decisions (summary)

1. **Adapter pattern: protocol seam in ZebraVault + conformance files under
   `Sources/Zebra/Adapters/`** on the cmux side (Option C). Fall back to closure
   injection on `ZebraServices` for non-`ObservableObject` utilities (e.g.,
   `cmuxAccentColor`). No existing cmux source files outside `Sources/Zebra/**` get
   modified.
2. **SPM deps from ZebraVault:** `MarkdownUI` (remote), `Bonsplit` (vendor),
   `CMUXDebugLog` (sibling package).
3. **Mirrors in ZebraVault:** `FocusFlashPattern` (trivial enum).
4. **Localization:** keep shared `Resources/Localizable.xcstrings`. No callsite rewrite.
5. **Tests:** seed `Packages/ZebraVault/Tests/ZebraVaultTests/` with
   `GoalFrontmatterParserTests` + `BrainObjectParserGoalStatusTests`. Leave
   `FileDropOverlayViewTests` in `cmuxTests/`.

## Risks / unresolved

- **`Workspace` surface for `ZebraMarkdownPanelView`.** Workspace methods Zebra uses
  return `MarkdownPanel?` / `TerminalPanel?`. Protocols for these return types need to
  match concrete cmux types and ZebraVault protocol views. Returning
  `(some ZebraMarkdownPanelModel)?` works in Swift 5.7+ but stresses generic boundaries.
  Mitigation at design time: where Zebra doesn't actually consume the returned panel,
  collapse the return to `Bool` / `Void`; reserve protocol return types for cases Zebra
  reads members.
- **`ObservableObject` through a protocol.** `@ObservedObject var panel: any ZebraMarkdownPanelModel`
  compiles in modern Swift but has SwiftUI subtleties around redraw triggers. Prototype
  in step 3.1 before committing the full migration.
- **`workspace.objectWillChange` Combine sink** in `ActiveMarkdownPathsObserver`. Mitigation:
  expose `var objectWillChangePublisher: AnyPublisher<Void, Never> { get }` on the
  protocol; conformance returns `objectWillChange.eraseToAnyPublisher()`.
- **`PaneID` re-export.** ZebraVault `@_exported import Bonsplit` so cmux call sites
  don't need to import both modules.
- **pbxproj surgery.** Removing ~240 Zebra entries from pbxproj is the largest single
  pbxproj edit in this project. Step 3.4 must use a tested script + backup branch.
- **Estimated effort:** plan said 1.5–2 weeks. Audit suggests ~60% goes to the protocol
  seam design + `ObservableObject`-via-protocol verification for `ZebraMarkdownPanelView`;
  remaining ~40% is mechanical SPM scaffold + pbxproj cleanup. Estimate holds.

## Next steps

1. Commit this RFC on `phase3-spm`, push for review.
2. **(3.1)** Scaffold `Packages/ZebraVault/Package.swift` with empty target + the three
   SPM deps + initial protocol files. Confirm `swift build` passes for the empty
   package.
3. **(3.2)** Build the protocol seam for the **markdown panel** slice first (deepest
   coupling): protocols, cmux-side conformance file under `Sources/Zebra/Adapters/`,
   prototype move of `ZebraMarkdownPanelView` into the package.
4. If 3.2 is clean → migrate remaining slices in order: Sidebar → BrainObjectInspector
   → MarkdownChatPill → VerticalTabsSidebar → Pickers → Panels → Environment.
5. **(3.4)** pbxproj surgery — remove Zebra file entries, add `Packages/ZebraVault` as
   a local package, add `import ZebraVault` where required.
6. **(3.5)** Touchpoint guard + manual regression checklist (sidebar modes, vault
   selector, markdown panel inspector + chat pill, settings, `cmd-click .md`).
7. Push, PR, merge to `main`.
