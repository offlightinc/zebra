# Merge Review - ee1c3de98

Target: `ee1c3de98 Merge remote-tracking branch 'upstream/main'`

Follow-up reviewed: `48490db8a Fix merge regressions in ee1c3de98 (upstream/main merge)`

Date: 2026-05-17

## Summary

- Build / launch: OK by manual `merge-test` app verification. I did not run local tests per repo policy.
- Xcode project load: OK with escalated `xcodebuild -project cmux.xcodeproj -list`.
- Merge shape: upstream side 91 commits, zebra side 76 commits.
- Main conclusion after follow-up `48490db8a`: no blocking merge-regression findings remain from this review.

## Current Working Tree

After follow-up `48490db8a`, the working tree is clean except for this review document:

- `?? docs/merge-review-ee1c3de98.md`

The previously observed dirty `ghostty` checkout is resolved: checked-out submodule, `HEAD:ghostty`, and `upstream/main:ghostty` all point to `aef980e27b584a9d914f1ff0499b13c6ed1973e0`.

## 1. Merge Metadata

- `git log --oneline -1 ee1c3de98`: target merge commit confirmed.
- Current `HEAD`: `48490db8a139eb3a094cc10eb4b97fa9acd47a8a`.
- Reviewed merge commit: `ee1c3de980751d94ee24dd80cc2911eb48d76ea4`.
- Merge base of parents: `5829da2d9f53c2030f7be1c3d282f118c9893432`.
- Upstream commits merged: 91.
- Zebra-side commits at merge: 76.
- `git diff --shortstat upstream/main HEAD -- Sources/ Resources/ cmuxTests/ scripts/ docs/ CLAUDE.md`: 84 files, +12,736 / -37. This is consistent with Zebra-only code plus seam files.

## 2. Build / Regression Check

| Area | Result | Notes |
| --- | --- | --- |
| Debug build / launch | OK | User verified with tagged `merge-test` app. |
| Unit target build | Not run | Repo policy says not to run tests locally; user already confirmed build. |
| Xcode project load | OK | `xcodebuild -project cmux.xcodeproj -list` succeeds when allowed to use Xcode caches. |
| Manual UI regression matrix | Partial | I could not drive the GUI via Computer Use in this session (`Could not find Service app`). Treat user `merge-test` verification as primary manual signal. |

## 3. Conflict Resolution Review

### A. Ghostty build scripts

Status: OK after follow-up `48490db8a`.

- `ghostty` is clean and aligned to `aef980e27...`.
- `scripts/ensure-ghosttykit.sh` restores `-Dcrash-report-subdir="$GHOSTTYKIT_CRASH_REPORT_SUBDIR"`.
- `scripts/build-ghostty-cli-helper.sh` restores `-Dcrash-report-subdir=cmux/crash`.

### B. `Sources/Panels/MarkdownPanel.swift`

Status: OK.

- Upstream `GlobalSearchCoordinator` capture/purge calls are present.
- Zebra `didCloseNotification` and close notification post are present.
- Zebra `updateFrontmatter(key:value:)` uses `BrainFrontmatterWriter`.
- Zebra-only panel state (`parse`, `showsInspector`, `chatCompanion*`) is no longer in the cmux model.

### C. `Sources/Panels/MarkdownPanelView.swift`

Status: OK.

- `git diff upstream/main HEAD -- Sources/Panels/MarkdownPanelView.swift` is empty.
- Upstream WKWebView markdown viewer is preserved verbatim.

### D. Zebra markdown renderer rename/factory

Status: OK after follow-up `48490db8a`.

- `ZebraMarkdownPanelView` exists in `Sources/Zebra/Panels/ZebraMarkdownPanelView.swift`.
- Factory calls `ZebraMarkdownPanelView(...)`.
- `MarkdownPanelViewContext` no longer carries unused `appearance`.

### E. `Sources/ContentView.swift`

Status: OK after follow-up `48490db8a`.

- Merge commit keeps `SidebarSlots` and `sidebarComposer.compose(slots)`.
- Merge commit incorrectly kept a stale `FirstMouseGatedHostingOverlay()` call while upstream removed the type definition.
- Follow-up commit removes the stale overlay call. `rg FirstMouseGatedHostingOverlay` now returns no source references.
- `ContentView` still has seam-level diff only; no Zebra store references remain in `ContentView`.

### F. `Sources/Panels/PanelContentView.swift`

Status: OK.

- Uses `\.markdownPanelViewFactory`.
- Does not pass unused `appearance` through the markdown factory seam.
- No `Workspace` parameter threading remains.

### G. `Resources/Localizable.xcstrings`

Status: mostly OK; expected override no longer exists.

- upstream keys: 1931
- ours: 2076
- zebra-only: 145
- upstream-only drift: 0
- shared-content diffs: 0

The expected historical override for `settings.app.openMarkdownInCmuxViewer.subtitle` is no longer a diff; our value matches upstream. That may be fine if upstream adopted the desired wording, but it differs from the original review expectation of one shared-content diff.

### H. `cmux.xcodeproj/project.pbxproj`

Status: OK.

- Xcode project lists successfully.
- `Panels/MarkdownPanelView.swift` entry exists.
- `markdown-viewer` resource folder is registered.
- `CommandPaletteNucleoFFI` script phase is present.
- Zebra path references counted: 67, not 68. This appears consistent with `Sources/Zebra/Panels/Workspace+MarkdownSurface.swift` being removed because upstream now owns `Workspace.openOrFocusMarkdownSurface`.

## 4. Upstream Feature Adoption

Spot checks passed:

- Toggle Unread shortcut: localized strings, `KeyboardShortcutSettings`, menu, command palette, and tests present.
- Project rename to `cmux.xcodeproj`: current project is `cmux.xcodeproj`.
- Command palette settings/file toggles: `CommandPaletteSettingsToggle.swift` and settings search entries present.
- Runtime-only resume flag cleanup: `Packages/CMUXAgentLaunch` sanitizer policies and related tests are present.
- Workspace cwd inheritance: settings/search strings and command palette toggle present.
- Workspace unread indicator work: `mark-unread`, manual unread, and notification docs/tests present.
- Markdown viewer resources: 10 files exist in `Resources/markdown-viewer`, including `shell.html`, `marked.min.js`, `mermaid.min.js`, and Vega assets.
- Native command palette FFI: `Native/CommandPaletteNucleoFFI` exists, project script phase references `scripts/build-command-palette-nucleo-ffi.sh`.

The prompt's sample file names `Sources/CommandPalette/CommandPaletteNucleoFFI.swift` and `Sources/CommandPalette/Search/CommandPaletteSearchIndex.swift` do not match the actual upstream filenames. The actual files `CommandPaletteNucleoSearch.swift` and `CommandPaletteSearchOrchestrator.swift` are registered.

## 5. Phase 1/2/4 Preservation

Status: OK.

- `./scripts/check-upstream-touchpoints.sh`: OK, 87 files checked.
- `ContentView.swift`: no direct Zebra store references for `verticalTabsSidebarModeState`, `goalFileListStore`, etc.
- `MarkdownPanel.swift`: no `parse`, `showsInspector`, or `chatCompanion*` state; only `BrainFrontmatterWriter` call remains.
- `SessionPersistence.defaultSidebarWidth`: upstream value `200`.
- `WindowChromeMetrics`: no `secondRowHeight`.
- `ZebraSidebarMetrics.secondRowHeight`: present under `Sources/Zebra`.
- `WindowDragHandleView.extraLeadingInset`: still present and set from `ZebraServices`.
- `Workspace.openOrFocusMarkdownSurface`: present in `Sources/Workspace.swift`; Zebra extension file removed.

## Deleted File Review

The following were present on pre-merge Zebra (`ee1c3de98^1`) and absent in both upstream and current `HEAD`:

- `CLI/CMUXCLI+CodexConfigToml.swift`
- `cmuxTests/AuthManagerBrowserSignInTests.swift`
- `skills/cmux-debug-windows/SKILL.md`
- `skills/cmux-debug-windows/agents/openai.yaml`
- `skills/cmux-debug-windows/scripts/debug_windows_snapshot.sh`
- `skills/release/SKILL.md`
- `skills/release/agents/openai.yaml`

This looks like intentional Zebra-only deletion or repo skill cleanup, not an upstream omission, but it should be confirmed before pruning from history assumptions.

## Findings

No blocking findings after follow-up `48490db8a`.

Resolved during follow-up:

- Dirty `ghostty` submodule checkout resolved; parent, upstream, and working tree all point to `aef980e27...`.
- `crash-report-subdir` restored in both Ghostty build scripts.
- Stale `FirstMouseGatedHostingOverlay()` call removed; upstream no longer defines that type.
- Unused `appearance` parameter removed from the markdown factory seam.

## TODOs

1. Confirm deleted Zebra skill/test files are intentional.
2. Run focused manual UI checks on `merge-test`: mode rail, vault menu, markdown panel, inspector editing, chat pill, companion pane, Settings, Cmd-click `.md`, workspace create/close, terminal agent launch.

## Conclusion

The merge is structurally sound after follow-up `48490db8a`: upstream files/resources are present, the Xcode project loads, `MarkdownPanelView.swift` is upstream-verbatim, `ghostty` is clean, crash-report flags are restored, and Phase 1/2/4 isolation survived. Remaining risk is manual UI coverage, not an identified merge/code conflict issue.
