# cmux agent notes

## Zebra ↔ cmux 분리 원칙 (필수)

이 저장소는 `manaflow-ai/cmux` 의 fork (`offlightinc/zebra`). upstream rebase 비용을 막기 위해 모든 Zebra 작업은 다음 규칙을 따른다:

- **cmux 파일 직접 수정 금지.** upstream 코드에 닿아야 하면 EnvironmentKey / Composer slot / Factory closure / 프로토콜 seam 중 하나로 자국을 내고, 채우는 쪽은 Zebra 코드로만. 허용된 touchpoint 목록은 `docs/upstream-touchpoints.md`, 강제 가드는 `scripts/check-upstream-touchpoints.sh` (pre-commit hook 으로 깔림 — `scripts/setup.sh` 가 `core.hooksPath .githooks` 설정).
- **cmux 모델에 zebra-only 필드/메서드 추가 금지.** 필요하면 side-car controller 로 빼고 owner 는 `ZebraServices` (앱 전역). View 의 `@StateObject` / `onDisappear` 에 매면 split reparent 시 회귀 발생.
- **새 Zebra 파일의 default 위치는 `Packages/ZebraVault/Sources/ZebraVault/**` SPM 패키지.** cmux 의 `@EnvironmentObject` (`TabManager`, `SidebarSelectionState`) 를 읽거나 cmux 모델 내부 (`Workspace.bonsplitController`, `workspace.panels` 등) 를 직접 다뤄야만 하는 adapter 류는 예외적으로 `Sources/Zebra/` 아래 남긴다 (현재 10개 — `Adapters/`, `Environment/`, `Panels/`, `Sidebar/`, `VerticalTabsSidebar/ActiveMarkdownPathsObserver.swift`). 그 외에 `Sources/` 직하부나 `Sources/Panels/` 에 zebra 파일을 새로 추가하는 것은 금지.
- **ZebraVault 의 public API 는 cmux-측 adapter 가 실제로 부르는 것만.** 내부 view/store 는 internal 기본. cmux upstream 파일에서 `import ZebraVault` 는 `docs/upstream-touchpoints.txt` 의 허용 목록에 있는 파일에서만 (현재 `AppDelegate`, `ContentView`, `Sources/Panels/MarkdownPanel.swift`). 다른 cmux 파일에서 import 하려는 욕구가 들면 seam 이 부족하다는 신호.
- **cmux 모델을 Zebra 프로토콜에 conform 시킬 때는 `Sources/Zebra/Adapters/<Model>+ZebraVault.swift` 패턴으로.** 프로토콜은 ZebraVault 에서 `public` 으로 선언, conformance 는 cmux 측 adapter 파일에서 `extension <CmuxModel>: <ZebraProtocol> {}`. cmux upstream 파일을 한 줄도 안 만짐. Reference: `Sources/Zebra/Adapters/MarkdownPanel+ZebraVault.swift`.
- **SwiftUI 의 `@ObservedObject var X: any P` 패턴은 피하고 generic struct 로.** Protocol existential 위에 `@ObservedObject` 를 두면 SwiftUI 의 redraw 가 호출 사이트의 concrete type 정보를 못 받아 invalidation 이 어긋날 수 있다. 대신 view 를 `struct ZebraXView<Model: P>: View { @ObservedObject var model: Model }` 식으로 protocol 위에 generic 화. cmux 호출 사이트가 concrete type 으로 instantiate → SwiftUI 가 정상 publish/sink. Reference: `ZebraMarkdownPanelView<Model: ZebraMarkdownPanelModel>`.
- **`Resources/Localizable.xcstrings` 의 upstream 영역은 byte-identical 유지.** Zebra 신규 문자열은 같은 파일 끝의 Zebra append 블록에 추가. 별도 `.xcstrings` 카탈로그로 분리 금지 (SwiftUI 가 별도 table 로 컴파일해서 `String(localized:)` 가 못 찾음). ZebraVault 안의 신규 문자열도 같은 cmux 카탈로그에 둔다 — `Packages/ZebraVault/` 안에 별도 카탈로그를 만들면 `bundle: .module` 을 호출 사이트마다 명시해야 하는데, 누락 시 silent fallback 으로 영문만 노출되는 회귀 위험이 크다 (Phase 1.3 회귀 학습).

## Zebra overlay operating model (필수)

이 repo 의 기본값은 upstream cmux 이고, 최종 제품 판단은 Zebra overlay 를 통해 적용된다. 빌드/릴리즈/브랜딩/앱 ID/패키징/사용자 노출 기능을 다룰 때는 cmux 기본값을 곧바로 최종 Zebra 기본값으로 보지 말고, 먼저 Zebra overlay 가 있는지 확인한다.

- **작업 분류를 먼저 한다.** 요청이 upstream cmux 공통 동작인지, Zebra 제품 동작인지, 둘을 잇는 adapter/touchpoint 인지 구분한 뒤 진행한다.
- **Zebra 판단은 Zebra-owned overlay 에 둔다.** 새 정책/브랜딩/릴리즈 흐름/제품 전용 동작은 `Packages/ZebraVault/**`, `Sources/Zebra/**`, `scripts/build-zebra-*.sh`, 또는 명시된 adapter/touchpoint 로 둔다. upstream cmux 파일 변경은 마지막 선택지다.
- **앱 이름이 중요하면 Debug 빌드와 Zebra 릴리즈 빌드를 구분한다.** `./scripts/reload.sh --tag <tag>` 는 개발용 `cmux DEV <tag>.app` 을 만든다. Zebra 브랜드 산출물은 release overlay 가 만드는 `Zebra.app` / `dist/Zebra.dmg` 이다.
- **Zebra 브랜드 릴리즈는 `scripts/build-zebra-notarized-dmg.sh` 를 우선 확인한다.** 기본값은 app name `Zebra`, bundle id `com.offlight.zebra`, derived data `build-zebra-release`, DMG `dist/Zebra.dmg`.
- **`PRODUCT_NAME=Zebra` 를 xcodebuild 에 직접 넘기지 않는다.** 과거에 Swift package resource bundle 이름까지 `Zebra.bundle` 로 바뀌어 duplicate-output 빌드 실패가 났다. 검증된 방식은 upstream `cmux.app` 을 먼저 빌드하고, `Zebra.app` 으로 복사한 뒤 `Info.plist` 의 `CFBundleName`, `CFBundleDisplayName`, `CFBundleIdentifier` 를 패치하고 서명/노타라이즈하는 것이다.
- **히스토리가 필요하면 `/Users/dan/brain-offlight/ops/zebra-notarized-dmg-release.md` 를 먼저 확인한다.** 이 파일은 Zebra release overlay 의 런북이고, `AGENTS.md` 는 그 원칙을 작업 중 자동으로 따르게 하는 가드레일이다.

## Initial setup

Run the setup script to initialize submodules and build GhosttyKit:

```bash
./scripts/setup.sh
```

If this machine had the legacy external `local-offlight-brain-sync` plist
installed (via `~/brain-offlight/bin/install-local-offlight-brain-sync`),
disable it once now that zebra ships its own built-in brain sync:

```bash
./scripts/disable-legacy-brainsync.sh
```

The script `launchctl bootout` + `launchctl disable`s the
`ai.offlight.local-brain-sync` label and archives the plist to
`~/Library/Application Support/zebra/disabled-launchagents/`. It's a no-op
on machines that never installed the legacy plist. Reverse with
`./scripts/revert-legacy-brainsync.sh` if needed.

## Local dev

After making code changes, always run the reload script with a tag to build the Debug app:

```bash
./scripts/reload.sh --tag fix-zsh-autosuggestions
```

By default, `reload.sh` builds but does **not** launch the app. The script prints the `.app` path so the user can cmd-click to open it. After a successful build, it always terminates any running app with the same tag (so cmd-clicking launches the freshly-built binary instead of foregrounding the stale instance). Pass `--launch` to open the app automatically after the build:

```bash
./scripts/reload.sh --tag fix-zsh-autosuggestions --launch
```

`reload.sh` prints an `App path:` line with the absolute path to the built `.app`. Use that path to build a cmd-clickable `file://` URL. Steps:

1. Grab the path from the `App path:` line in `reload.sh` output.
2. Prepend `file://` and URL-encode spaces as `%20`. Do not hardcode any part of the path.
3. Format it as a markdown link using the template for your agent type.
4. In the final chat response, always include this clickable app link. Do not leave only the plain filesystem path, because clicking a plain path may not launch the app.

Example. If `reload.sh` output contains:
```
App path:
  /Users/someone/Library/Developer/Xcode/DerivedData/cmux-my-tag/Build/Products/Debug/cmux DEV my-tag.app
```

**Claude Code** outputs:
```markdown
=======================================================
[cmux DEV my-tag.app](file:///Users/someone/Library/Developer/Xcode/DerivedData/cmux-my-tag/Build/Products/Debug/cmux%20DEV%20my-tag.app)
=======================================================
```

**Codex** outputs:
```
=======================================================
[my-tag: cmux DEV my-tag.app](file:///Users/someone/Library/Developer/Xcode/DerivedData/cmux-my-tag/Build/Products/Debug/cmux%20DEV%20my-tag.app)
=======================================================
```

Never use `/tmp/cmux-<tag>/...` app links in chat output.
Never report a successful `reload.sh` build with only a raw `/Users/.../*.app` path. The user should be able to click the markdown link and launch the tagged app directly.

For CLI or socket dogfood against a tagged Debug app, use the tag-bound helper and set `CMUX_TAG`.
Do not use `/tmp/cmux-cli` for tagged dogfood, since that symlink points at the most recently
reloaded build and can target the user's main app socket.

```bash
CMUX_TAG=<tag> scripts/cmux-debug-cli.sh list-workspaces
CMUX_TAG=<tag> scripts/cmux-debug-cli.sh send --workspace workspace:1 --surface surface:1 "echo ok"
```

The helper refuses to run without `CMUX_TAG`, targets `/tmp/cmux-debug-<tag>.sock`, and uses the
matching tagged CLI from `~/Library/Developer/Xcode/DerivedData/cmux-<tag>/...`. It also scrubs
ambient cmux terminal context (`CMUX_SOCKET`, `CMUX_SOCKET_PASSWORD`, workspace/surface/tab/panel
IDs, cmuxd socket, and debug log), then sets `CMUX_SOCKET_PATH`, `CMUX_BUNDLE_ID`, and
`CMUX_BUNDLED_CLI_PATH` for the selected tag.

After making code changes, always use `reload.sh --tag` to build. **Never run bare `xcodebuild` or `open` an untagged `cmux DEV.app`.** Untagged builds share the default debug socket and bundle ID with other agents, causing conflicts and stealing focus.

```bash
./scripts/reload.sh --tag <your-branch-slug>
```

Codex note: run `./scripts/reload.sh` with escalated permissions from the start. The script writes
GhosttyKit cache locks under `~/.cache/cmux/ghosttykit`, which is outside the Codex workspace
sandbox. If Codex runs it without escalation, `ensure-ghosttykit.sh` can loop forever printing
`Waiting for GhosttyKit cache lock...` because the lock `mkdir` fails with `Operation not permitted`.
When requesting approval, keep the prefix narrow to `./scripts/reload.sh`; do not request broad
shell prefixes such as `bash`, `zsh`, or `python3`.

If you only need to verify the build compiles (no launch), use a tagged derivedDataPath:

```bash
xcodebuild -project cmux.xcodeproj -scheme cmux -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/cmux-<your-tag> build
```

When rebuilding GhosttyKit.xcframework, always use Release optimizations:

```bash
cd ghostty && zig build -Demit-xcframework=true -Dxcframework-target=universal -Doptimize=ReleaseFast
```

When rebuilding cmuxd for release/bundling, always use ReleaseFast:

```bash
cd cmuxd && zig build -Doptimize=ReleaseFast
```

`reload` = build the Debug app (tag required) and terminate any running app with the same tag. Pass `--launch` to also open the freshly-built app:

```bash
./scripts/reload.sh --tag <tag>
./scripts/reload.sh --tag <tag> --launch
```

`reloadp` = kill and launch the Release app:

```bash
./scripts/reloadp.sh
```

`reloads` = kill and launch the Release app as "cmux STAGING" (isolated from production cmux):

```bash
./scripts/reloads.sh
```

`reload2` = reload both Debug and Release (tag required for Debug reload):

```bash
./scripts/reload2.sh --tag <tag>
```

For parallel/isolated builds (e.g., testing a feature alongside the main app), use `--tag` with a short descriptive name:

```bash
./scripts/reload.sh --tag fix-blur-effect
```

This creates an isolated app with its own name, bundle ID, socket, and derived data path so it runs side-by-side with the main app. Important: use a non-`/tmp` derived data path if you need xcframework resolution (the script handles this automatically).

Before launching a new tagged run, clean up any older tags you started in this session (quit old tagged app + remove its `/tmp` socket/derived data).

## Cloud VM secrets

Cloud VM build, test, and local dev scripts use provider secrets from `~/.secrets/cmux.env`.

- `E2B_API_KEY`
- `FREESTYLE_API_KEY`
- R2 upload vars used by `web/scripts/build-cloud-vm-images.ts` when creating Freestyle snapshots

Load them with:

```bash
set -a
source ~/.secrets/cmux.env
set +a
```

`~/.secrets/cmuxterm-dev.env` is for local Stack/web env and does not contain the provider build keys.
`bun dev` sources `~/.secrets/cmux.env` first when present, then `~/.secrets/cmuxterm-dev.env` so
cmuxterm-specific Stack settings override broader cmux secrets. The web dev loader still accepts
the legacy `~/.secret/cmuxterm.env` and `~/.secrets/cmuxterm.env` paths while machines migrate.

## Backend TypeScript

Default backend TypeScript to Effect. For code under `web/app/api/**`, `web/services/**`, and
backend scripts that touch providers, databases, auth, rate limits, retries, timeouts, or telemetry,
model workflows as `Effect.Effect` values with typed domain errors and explicit service
dependencies. Keep Next route handlers thin: parse the request, run one Effect program at the
boundary, map typed errors to HTTP responses, and treat unexpected defects separately.

Use plain TypeScript only for trivial data shapes, constants, config files, frontend React code, or
small glue where Effect would add ceremony without improving failure handling.

Cloud VM backend logic must stay in Vercel route handlers and Effect services backed by Postgres.
Do not reintroduce Rivet or a raw actor protocol for this feature unless a later architecture doc
explicitly changes the control plane.

Production and staging Cloud VM Postgres should use the Vercel Marketplace AWS Aurora PostgreSQL
OIDC/RDS IAM path. Runtime env names are `CMUX_DB_DRIVER=aws-rds-iam`, `AWS_ROLE_ARN`,
`AWS_REGION`, `PGHOST`, `PGPORT`, `PGUSER`, and `PGDATABASE`. Run production/staging migrations
with `bun db:migrate:aws-rds-iam`; never run Drizzle migrations from Vercel build or route startup.
Local development keeps using the `CMUX_PORT`-derived Docker Postgres path from `bun dev`.
Cloud VM create pricing gates should use Stack Auth team payment items when enabled. Postgres remains
the source of truth for VM lifecycle, active VM limits, idempotency, and usage events.

## Debug event log

When adding debug event instrumentation, put events (keys, mouse, focus, splits, tabs)
in the unified DEBUG build log:

This section describes the required destination and shape for debug logs when they
are added. It is not a blanket requirement to add debug logs to every new code path.
Most temporary probes should be added only during the dogfood debug loop and removed
before merge.

```bash
tail -f "$(cat /tmp/cmux-last-debug-log-path 2>/dev/null || echo /tmp/cmux-debug.log)"
```

- Untagged Debug app: `/tmp/cmux-debug.log`
- Tagged Debug app (`./scripts/reload.sh --tag <tag>`): `/tmp/cmux-debug-<tag>.log`
- `reload.sh` writes the current path to `/tmp/cmux-last-debug-log-path`
- `reload.sh` writes the selected dev CLI path to `/tmp/cmux-last-cli-path`
- `reload.sh` updates `/tmp/cmux-cli` and `$HOME/.local/bin/cmux-dev` to that CLI

- Implementation: `Packages/CMUXDebugLog/Sources/CMUXDebugLog/DebugEventLog.swift`
- App shim: `Sources/App/DebugLogging.swift`
- Free function `cmuxDebugLog("message")` — logs with timestamp and appends to file in real time from cmux code
- The package implementation and app shim are `#if DEBUG`; all call sites must be wrapped in `#if DEBUG` / `#endif`
- 500-entry ring buffer; `CMUXDebugLog.DebugEventLog.shared.dump()` writes full buffer to file
- Key events logged in `AppDelegate.swift` (monitor, performKeyEquivalent)
- Mouse/UI events logged inline in views (ContentView, BrowserPanelView, etc.)
- Focus events: `focus.panel`, `focus.bonsplit`, `focus.firstResponder`, `focus.moveFocus`
- Bonsplit events: `tab.select`, `tab.close`, `tab.dragStart`, `tab.drop`, `pane.focus`, `pane.drop`, `divider.dragStart`

## Regression test commit policy

When adding a regression test for a bug fix, use a two-commit structure so CI proves the test catches the bug:

1. **Commit 1:** Add the failing test only (no fix). CI should go red.
2. **Commit 2:** Add the fix. CI should go green.

This makes it visible in the GitHub PR UI (Commits tab, check statuses) that the test genuinely fails without the fix.

## Shared behavior policy

- When a behavior is exposed through multiple entrypoints (keyboard shortcut, command palette, context menu, CLI, settings, debug menu), implement one shared action/model path and verify every entrypoint that should invoke it. Do not patch one surface while leaving the others with duplicated logic.
- For optimistic UI or CLI updates, keep one mutation path, record pending state with a request id or previous snapshot, reconcile from the authoritative result, and handle failure with an explicit rollback or error state. Do not let each entrypoint maintain its own optimistic copy.
- When a user says tests missed a bug, add or adjust behavior-level coverage around the exact repro path before claiming the fix is complete.

## Debug menu

The app has a **Debug** menu in the macOS menu bar (only in DEBUG builds). Use it for visual iteration:

- **Debug > Debug Windows** contains panels for tuning layout, colors, and behavior. Entries are alphabetical with no dividers.
- To add a debug toggle or visual option: create an `NSWindowController` subclass with a `shared` singleton, add it to the "Debug Windows" menu in `Sources/cmuxApp.swift`, and add a SwiftUI view with `@AppStorage` bindings for live changes.
- When the user says "debug menu" or "debug window", they mean this menu, not `defaults write`.

## Pitfalls

- **Custom UTTypes** for drag-and-drop must be declared in `Resources/Info.plist` under `UTExportedTypeDeclarations` (e.g. `com.splittabbar.tabtransfer`, `com.cmux.sidebar-tab-reorder`).
- Do not add an app-level display link or manual `ghostty_surface_draw` loop; rely on Ghostty wakeups/renderer to avoid typing lag.
- **Typing-latency-sensitive paths** (read carefully before touching these areas):
  - `WindowTerminalHostView.hitTest()` in `TerminalWindowPortal.swift`: called on every event including keyboard. All divider/sidebar/drag routing is gated to pointer events only. Do not add work outside the `isPointerEvent` guard.
  - `TabItemView` in `ContentView.swift`: uses `Equatable` conformance + `.equatable()` to skip body re-evaluation during typing. Do not add `@EnvironmentObject`, `@ObservedObject` (besides `tab`), or `@Binding` properties without updating the `==` function. Do not remove `.equatable()` from the ForEach call site. Do not read `tabManager` or `notificationStore` in the body; use the precomputed `let` parameters instead.
  - `TerminalSurface.forceRefresh()` in `GhosttyTerminalView.swift`: called on every keystroke. Do not add allocations, file I/O, or formatting here.
- **Terminal find layering contract:** `SurfaceSearchOverlay` must be mounted from `GhosttySurfaceScrollView` in `Sources/GhosttyTerminalView.swift` (AppKit portal layer), not from SwiftUI panel containers such as `Sources/Panels/TerminalPanelView.swift`. Portal-hosted terminal views can sit above SwiftUI during split/workspace churn.
- **Submodule safety:** When modifying a submodule (ghostty, vendor/bonsplit, etc.), always push the submodule commit to its remote `main` branch BEFORE committing the updated pointer in the parent repo. Never commit on a detached HEAD or temporary branch — the commit will be orphaned and lost. Verify with: `cd <submodule> && git merge-base --is-ancestor HEAD origin/main`.
- **All user-facing strings must be localized.** Use `String(localized: "key.name", defaultValue: "English text")` for every string shown in the UI (labels, buttons, menus, dialogs, tooltips, error messages). Keys go in `Resources/Localizable.xcstrings` with translations for all supported languages (currently English and Japanese). Never use bare string literals in SwiftUI `Text()`, `Button()`, alert titles, etc.
- **Shortcut policy:** Every new cmux-owned keyboard shortcut must be added to `KeyboardShortcutSettings`, visible/editable in Settings, supported in `~/.config/cmux/cmux.json`, and documented in the keyboard shortcut and configuration docs.
- **Snapshot boundary for list subtrees.** In any SwiftUI panel whose `body` contains a `LazyVStack` / `LazyHStack` / `List` / `ForEach` of rows, no view below that boundary may hold a reference to an `ObservableObject` / `@Observable` store (no `@ObservedObject`, `@EnvironmentObject`, `@StateObject`, `@Bindable`, or even a plain `let store: SomeStore` property). Rows and drop-gaps receive immutable value snapshots plus closure action bundles only. Violating this reintroduces the "orthogonal @Published change invalidates every row and thrashes `LazyLayoutViewCache`" class of 100% CPU spin loop that hit the Sessions panel and the workspace sidebar (https://github.com/manaflow-ai/cmux/issues/2586). Reference pattern: `IndexSectionActions` / `SectionGapActions` / `SessionSearchFn` in `Sources/SessionIndexView.swift`.
- **No state mutation inside view-body computations.** A function called from `body` (directly or through a helper) must not write `@Published` state, schedule a `Task { @MainActor in store.x = … }`, or `DispatchQueue.main.async` a store write. That creates a re-render feedback loop and pegs the main thread (same root-cause family as the snapshot-boundary rule). State-changing work triggered by "new data appeared" belongs in a `reload()` completion, a `didSet`, or a property-observer — never in the projection that feeds `ForEach`.

## Test quality policy

- Do not add tests that only verify source code text, method signatures, AST fragments, or grep-style patterns.
- Do not add tests that read checked-in metadata or project files such as `Resources/Info.plist`, `project.pbxproj`, `.xcconfig`, or source files only to assert that a key, string, plist entry, or snippet exists.
- Tests must verify observable runtime behavior through executable paths (unit/integration/e2e/CLI), not implementation shape.
- For metadata changes, prefer verifying the built app bundle or the runtime behavior that depends on that metadata, not the checked-in source file.
- If a behavior cannot be exercised end-to-end yet, add a small runtime seam or harness first, then test through that seam.
- If no meaningful behavioral or artifact-level test is practical, skip the fake regression test and state that explicitly.

## Socket command threading policy

- Do not use `DispatchQueue.main.sync` for high-frequency socket telemetry commands (`report_*`, `ports_kick`, status/progress/log metadata updates).
- For telemetry hot paths:
  - Parse and validate arguments off-main.
  - Dedupe/coalesce off-main first.
  - Schedule minimal UI/model mutation with `DispatchQueue.main.async` only when needed.
- Commands that directly manipulate AppKit/Ghostty UI state (focus/select/open/close/send key/input, list/current queries requiring exact synchronous snapshot) are allowed to run on main actor.
- If adding a new socket command, default to off-main handling; require an explicit reason in code comments when main-thread execution is necessary.

## Socket focus policy

- Socket/CLI commands must not steal macOS app focus (no app activation/window raising side effects).
- Only explicit focus-intent commands may mutate in-app focus/selection (`window.focus`, `workspace.select/next/previous/last`, `surface.focus`, `pane.focus/last`, browser focus commands, and v1 focus equivalents).
- All non-focus commands should preserve current user focus context while still applying data/model changes.

## Testing policy

**Never run tests locally.** All tests (E2E, UI, python socket tests) run via GitHub Actions or on the VM.

- **E2E / UI tests:** trigger via `gh workflow run test-e2e.yml` (see cmuxterm-hq CLAUDE.md for details)
- **Unit tests:** `xcodebuild -scheme cmux-unit` is safe (no app launch), but prefer CI
- **Python socket tests (tests_v2/):** these connect to a running cmux instance's socket. Never launch an untagged `cmux DEV.app` to run them. If you must test locally, use a tagged build's socket (`/tmp/cmux-debug-<tag>.sock`) with `CMUX_SOCKET_PATH=/tmp/cmux-debug-<tag>.sock`
- **Never `open` an untagged `cmux DEV.app`** from DerivedData. It conflicts with the user's running debug instance.

## Ghostty submodule workflow

Ghostty changes must be committed in the `ghostty` submodule and pushed to the `manaflow-ai/ghostty` fork.
Keep `docs/ghostty-fork.md` up to date with any fork changes and conflict notes.

```bash
cd ghostty
git remote -v  # origin = upstream, manaflow = fork
git checkout -b <branch>
git add <files>
git commit -m "..."
git push manaflow <branch>
```

To keep the fork up to date with upstream:

```bash
cd ghostty
git fetch origin
git checkout main
git merge origin/main
git push manaflow main
```

Then update the parent repo with the new submodule SHA:

```bash
cd ..
git add ghostty
git commit -m "Update ghostty submodule"
```

## Release

Use the `/release` command to prepare a new release. This will:
1. Determine the new version (bumps minor by default)
2. Gather commits since the last tag and update the changelog
3. Update `CHANGELOG.md` (the docs changelog page at `web/app/docs/changelog/page.tsx` reads from it)
4. Run `./scripts/bump-version.sh` to update both versions
5. Commit, run `./scripts/release-pretag-guard.sh`, tag, and push

Version bumping:

```bash
./scripts/bump-version.sh          # bump minor (0.15.0 → 0.16.0)
./scripts/bump-version.sh patch    # bump patch (0.15.0 → 0.15.1)
./scripts/bump-version.sh major    # bump major (0.15.0 → 1.0.0)
./scripts/bump-version.sh 1.0.0    # set specific version
```

This updates both `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` (build number). The build number is auto-incremented and is required for Sparkle auto-update to work.

Before creating a release tag, run:

```bash
./scripts/release-pretag-guard.sh
```

If it fails, run `./scripts/bump-version.sh`, commit the build-number bump, then retry tagging.

Manual release steps (if not using the command):

```bash
./scripts/release-pretag-guard.sh
git tag vX.Y.Z
git push origin vX.Y.Z
gh run watch --repo manaflow-ai/cmux
```

Notes:
- Requires GitHub secrets: `APPLE_CERTIFICATE_BASE64`, `APPLE_CERTIFICATE_PASSWORD`,
  `APPLE_SIGNING_IDENTITY`, `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, `APPLE_TEAM_ID`.
- The release asset is `cmux-macos.dmg` attached to the tag.
- README download button points to `releases/latest/download/cmux-macos.dmg`.
- Versioning: bump the minor version for updates unless explicitly asked otherwise.
- Changelog: update `CHANGELOG.md`; docs changelog is rendered from it.
