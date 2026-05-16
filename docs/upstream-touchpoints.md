# Upstream Touchpoints

This document lists every cmux (`upstream/main`) file that Zebra is allowed to
modify, and the reason. Any other cmux file change in a Zebra PR is a
**regression** of the adapter separation we did in Phase 1 / Phase 2 of the
[zebra-upstream isolation design](https://github.com/offlightinc/b-brain/blob/main/docs/designs/zebra-upstream-isolation.md).

The companion script `scripts/check-upstream-touchpoints.sh` reads the
machine-readable allowlist in `docs/upstream-touchpoints.txt`.

## How Zebra is allowed to touch a cmux file

Each touchpoint should fit one of these seam types — `Sources/Zebra/` provides
the implementation, the cmux file only exposes the slot:

| Seam | Where it lives | What cmux contributes |
|---|---|---|
| EnvironmentKey | `Sources/Zebra/.../*` | A `@Environment(\.zebraThing)` read + default value |
| Composer / slot factory | `Sources/Zebra/Sidebar/SidebarComposer.swift`, `Sources/Zebra/Panels/MarkdownPanelViewFactory.swift` | An env value lookup + `factory(context)` call |
| Side-car controller | `Sources/Zebra/Panels/MarkdownPanelController.swift` | A `Notification.Name` declaration + one-line post |
| DI container | `Sources/Zebra/Environment/ZebraServices.swift` | `.injectIntoEnvironment(...)` call in app entrypoint |
| Localization | `Resources/Localizable.xcstrings` zebra-append block | n/a — single file by SwiftUI's table model |
| Project plumbing | `GhosttyTabs.xcodeproj/project.pbxproj`, `cmuxTests/FileDropOverlayViewTests.swift` | `Sources/Zebra/**` file entries + test ContentView injection |

## Allowed touchpoints

| File | Seam | Reason |
|---|---|---|
| `Sources/AppDelegate.swift` | DI container | `ZebraServices.makeDefault().injectIntoEnvironment(...)` wraps the root `ContentView` once per `createMainWindow`. |
| `Sources/ContentView.swift` | Composer slot + env key | Builds `SidebarSlots(workspaceList: …, defaultFooter: …, onSendFeedback: …)` and calls `sidebarComposer.compose(slots)`. Reads `\.sidebarExtraLeadingInset` for fullscreen control padding. |
| `Sources/Panels/PanelContentView.swift` | View factory | `\.markdownPanelViewFactory` env lookup + fall-through when nil. |
| `Sources/Panels/MarkdownPanel.swift` | Side-car cleanup | `static let didCloseNotification` + `NotificationCenter.default.post(...)` in `close()`. `updateFrontmatter(key:value:)` stays because it has to mutate `@Published private(set) var content`. |
| `Sources/WorkspaceContentView.swift` | View factory plumbing | Passes `workspace:` to `PanelContentView` so the markdown view factory can pull `Workspace`-bound helpers out of the context. |
| `Sources/SessionPersistence.swift` | Preference override (TODO migrate) | `defaultSidebarWidth: 300` (vs upstream `200`) — Zebra ships a wider rail-aware sidebar by default. Single constant; eventually move to a `\.zebraDefaultSidebarWidth` env value during a future Phase 1.4 finish-up. |
| `Sources/WindowChromeMetrics.swift` | Preference override (TODO migrate) | `SidebarWorkspaceListMetrics.secondRowHeight` is consumed only by Zebra Tasks/Goals modes. Phase 1.4 plans to move it to `Sources/Zebra/Sidebar/ZebraSidebarMetrics.swift`. |
| `Sources/WindowDragHandleView.swift` | Preference override (TODO migrate) | `MinimalModeSidebarTitlebarControlsMetrics.leadingInset` adds `VerticalTabsSidebarModeRail.fixedWidth`. Same `\.sidebarExtraLeadingInset` pattern Phase 1.2 used for fullscreen controls would cover this; pending a verification pass that the minimal-mode and fullscreen geometries match. |
| `Resources/Localizable.xcstrings` | Localization | Zebra-only keys appended after upstream's last entry. The upstream block stays byte-identical (one historical override on `settings.app.openMarkdownInCmuxViewer.subtitle`). **Never** split into a second `.xcstrings` — SwiftUI compiles it into a separate string table and `String(localized:)` without `table:` won't find it (Phase 1.3 regression learning). |
| `cmuxTests/FileDropOverlayViewTests.swift` | DI container in tests | `ZebraServices.makeDefault().injectIntoEnvironment(ContentView().zebraStoreBindings()...)` mirrors the prod entrypoint. |
| `GhosttyTabs.xcodeproj/project.pbxproj` | Project plumbing | Zebra file entries under `Sources/Zebra/**`. Don't touch any other group / target. |
| `CLAUDE.md` | Docs | The "Zebra ↔ cmux 분리 원칙" section. |
| `docs/upstream-touchpoints.md` / `docs/upstream-touchpoints.txt` | Docs / lint | This file and the guard list. |

## Disallowed (with examples that have come up)

- **New `@EnvironmentObject` for a Zebra store on a cmux struct.** Read via `@Environment(\.zebra)?.foo` if you need ephemeral access; otherwise attach `.zebraStoreBindings()` once at the root and consume the store inside the Zebra view.
- **New stored fields on `MarkdownPanel` (or any other cmux model) that only matter for Zebra workflows.** Put them on a side-car controller owned by `ZebraServices`. Hard constraints documented in `Sources/Zebra/Panels/MarkdownPanelController.swift`.
- **Adding `import Bonsplit` or any Zebra-only module to a cmux file.** Means the adapter seam is missing or being bypassed.
- **Inline reformatting `Resources/Localizable.xcstrings`'s upstream block.** That nukes the byte-identical guarantee and turns every upstream string PR into a merge conflict.

## What to do if you need a new touchpoint

1. Add the seam to the cmux file (env key / factory / slot / notification — whichever fits).
2. Implement the Zebra side under `Sources/Zebra/**`.
3. Add the cmux file to `docs/upstream-touchpoints.txt` with a comment explaining the seam.
4. Update the table above.
