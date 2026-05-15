# Goals 사이드바 Task-style 통일 계획

## 목표
Goals 사이드바의 세 모드(**구조 / 주기 / 상태**)의 헤더·행 vocabulary 를 Tasks 사이드바와 일치시키고, 두 도메인의 status 파싱 정책도 통일한다.

설계 원칙: **신규 도메인 컴포넌트는 0개**. 대신 Tasks 가 단독 소유하던 컴포넌트를 도메인-중립 이름으로 추출/이동해서 Goals 도 같이 쓴다. 새 기능은 "상태 모드에서 status 변경 가능" 하나뿐이고, 그 구현은 `TaskListRow` 의 status 버튼 패턴 + 기존 `EditableGoalStatusPill` 의 picker 코드 = 거의 카피.

추가 결정: Goal status parser 의 "unknown → `.draft` 흡수" 정책을 Task 와 동일한 "보존 + UI 표시" 로 변경 (C0). UI 통합 작업의 선행 조건이자 데이터 무결성을 위한 변경.

## 현재 상태 (factual)

| 영역 | Goals 현재 | Tasks 현재 |
|---|---|---|
| Section header | `GoalCollapsibleHeader` (chevron **좌측**, font 11pt semibold uppercase fgMute) · `GoalGroupHeader` (chevron 없음) | `TaskGroupHeader` (chevron **우측**, font 10.5pt bold tracking 0.8 fgMute, count 11pt fgFaint) |
| Row leading | `flatRowLeadingInset = 16` 추가 inset → 타이틀이 헤더보다 들여쓰기 | `.padding(.horizontal, 14)` 만 — 헤더와 같은 좌측 라인 |
| Row chrome | background tint 만 (hover 없음, bar 없음) | 좌측 2pt accent bar + selection bg tint + hover tint |
| Status 표시 | 없음 | 14×14 `StatusGlyph` 버튼, 탭 → `TaskStatusPicker` popover, write-back via `BrainFrontmatterWriter.setScalar("status", …)` |
| Status parser 정책 | unknown → `.draft` 흡수 (raw 손실) | unknown 보존 + `unrecognizedStatusRaw` + UI `?` glyph |
| Glyph 모델 | `glyphMapping(BrainGoalStatus) -> BrainTaskStatus` 어댑터로 task vocabulary 차용 (lossy: archived↔canceled 같은 모양) | `StatusGlyph(status: BrainTaskStatus)` 가 도메인 직접 의존 |

> 메모: chevron 위치는 **우측** (Task 와 동일). 현 `GoalCollapsibleHeader` 가 chevron 을 좌측에 두던 것을 `SidebarSectionHeader` (C1) 로 교체하면서 우측으로 이동한다.

## 정책 통일 — Goal status parser (C0)

본 작업의 선행 정책 결정. UI 코드 변경 전에 데이터 모델 정책부터 통일한다.

### 현재 상태 (정책 차이)

| | Task parser | Goal parser |
|---|---|---|
| schema 위반값 (`status: actve` 오타) | 보존 — `status: nil` + `unrecognizedStatusRaw: "actve"` | 흡수 — `.draft` 로 강제, raw 버림 |
| 키 자체 없음 | `status: nil` | `.draft` |
| picker 노출 | `primaryCases` (legacy 제외) | `allCases` |

### 변경: Task 방식으로 통일 (Postel)

> 읽을 땐 관대하게 (위반값 살려서 표시), 쓸 땐 엄격하게 (picker 는 schema 만).

근거:
1. **데이터 손실 방지**. AI 가 주로 작성하지만 사용자도 손편집함. 오타 (`completd`) 가 silently `.draft` 로 흡수되면 사용자가 그걸 영원히 못 발견. 본 작업의 목표인 "UI 로 편하게 수정" 과 정면 충돌.
2. **UI 가 데이터 청소 도구가 됨**. `?` glyph 표시 → 사용자가 알아채고 picker 로 정정 → raw 클리어.
3. **공통화 더 깊게 가능**. 두 도메인 정책이 같아지면 status 버튼 UI 분기 모양이 동일 → 향후 generic 컴포넌트로 묶을 여지.

### 구체 변경

1. `GoalFrontmatterParser.swift`: `BrainGoalStatus(rawValue: …) ?? .draft` → `BrainGoalStatus(rawValue: …)` (nil 보존) + raw 가 있고 enum 매핑 실패 시 `unrecognizedStatusRaw` 에 저장
2. `GoalEntry.status`: `BrainGoalStatus` → `BrainGoalStatus?` (optional)
3. `GoalEntry`: 신규 필드 `unrecognizedStatusRaw: String?`
4. `GoalEntry.with(...)`: TaskItem.with 와 동일한 시그너처 — `with(status: BrainGoalStatus?? = nil, unrecognizedStatusRaw: String?? = nil)` (이중 optional 로 "변경 안함" 과 "nil 로 설정" 구분)
5. `EditableGoalStatusPill`: `value` 가 optional 이 됨 (사실 이미 optional 받고 있음 — 변경 거의 없음). `value` 가 nil 이거나 `unrecognizedStatusRaw` 가 있을 때의 분기 시각이 Task 와 동일하도록 정렬.
6. `BrainGoalStatus` 의 `allCases` 그대로 picker 노출 (legacy 케이스 없음 — D3 차이는 유지).

### 영향 호출처

- `GoalsListView.StatusLayout.bucketize`: status 가 nil 또는 unrecognized 인 entry 의 bucket 처리. **결정**: archived 뒤에 "UNKNOWN" 그룹 추가 (Task 의 unrecognized 분기와 같은 vocabulary).
- `GoalOutlineRow` / `GoalCadenceRow` 의 completion 판정 (`status == .completed`): nil/optional 처리 → `status == .some(.completed)` 또는 if-let.
- 검색 시 `entry.status` 직접 비교하는 모든 곳: optional 정합 필요.

### 스코프

본 PR 에 포함하되 **별 commit (Commit C0)** 으로 분리 — 정책 변경과 UI 변경을 리뷰어가 구분해서 볼 수 있도록.

## 공통화 (도메인-중립 추출)

신규 컴포넌트가 아니라 **이미 Tasks 가 가진 코드의 이름·위치·접근 수준만 바꿔서** Goals 도 같이 쓸 수 있게 만드는 작업. 행위는 100% 보존.

### C1. `TaskGroupHeader` → `SidebarSectionHeader`
- 현 위치: `Sources/VerticalTabsSidebar/Tasks/TaskGroupHeader.swift`
- 새 위치: `Sources/VerticalTabsSidebar/Shared/SidebarSectionHeader.swift`
- struct 이름: `TaskGroupHeader` → `SidebarSectionHeader`
- 행위 변경 없음. `TaskListView` 의 호출부 한 줄과 Goals 호출부가 같은 이름 사용.
- (Goals 의 비-collapsible 루트 "Goals · N" 도 동일 컴포넌트, `onToggle: {}` / `isCollapsed: false` 로 호출 — 별도 variant 만들지 않음.)

### C2. StatusGlyph 시각 추상화 (StatusGlyphShape)
- 현 상태: `StatusGlyph(status: BrainTaskStatus)` — 시각 컴포넌트가 도메인 enum (BrainTaskStatus) 에 직접 의존. Goal 은 별도 `glyphMapping(BrainGoalStatus) -> BrainTaskStatus` 어댑터로 변환해 호출.
- 문제: 시각 vocabulary (5가지 도형) 와 도메인 enum 이 한 몸. Goal 같은 다른 도메인이 끼어들면 변환 단계 추가 필요. archived 와 canceled 처럼 도메인 의미는 다른데 시각만 같은 경우의 분리도 어려움.
- 변경 (옵션 D): **시각 vocabulary 를 별도 enum 으로 추상화** + 도메인 enum 이 자기 시각을 자기가 결정.

```swift
// 신규: Sources/Panels/BrainObjectInspector/StatusGlyphShape.swift
enum StatusGlyphShape: Hashable {
    case open          // ○ stroke-only
    case halfFilled    // 🌗
    case bar           // ─
    case check         // ✓
    case canceledBar   // ▬ + 흑
    // archived 가 시각 차별화될 거면 case 추가 (별 issue 참고)
}

// StatusGlyph 시그너처 변경
struct StatusGlyph: View {
    let shape: StatusGlyphShape
    var body: some View { /* shape switch */ }
}

// 호환성 init (점진 마이그레이션용)
extension StatusGlyph {
    init(status: BrainTaskStatus) { self.init(shape: status.glyphShape) }
}

// 도메인 enum 이 자기 시각 결정
extension BrainTaskStatus {
    var glyphShape: StatusGlyphShape { /* backlog/todo→open, inprogress→halfFilled, … */ }
}
extension BrainGoalStatus {
    var glyphShape: StatusGlyphShape { /* draft→open, active→halfFilled, blocked→bar, completed→check, archived→canceledBar */ }
}
```

- **glyphMapping 어댑터는 삭제됨** (taskStatus(for:) 자체가 불필요해짐). 변환 한 단계가 사라짐.
- 남은 함수 `goalStatusLabel(_:)` 은 `BrainGoalStatus.localizedLabel` extension 으로 옮김 (sentence case). 기존 `.label` (uppercase) 은 sentence-case 로 통일하고 section header 가 `.uppercased()` 책임 (이미 `SidebarSectionHeader` 가 그렇게 처리).
- 호출부 (사이드바 status 버튼, Inspector pills, OptionPicker glyph 클로저, picker) 는 `StatusGlyph(shape: status.glyphShape)` 패턴으로 점진 치환. 호환성 init 덕에 일괄 변경 부담 분산.
- `EditableGoalStatusPill` 은 어댑터 호출 → `entry.status.glyphShape` 직접 사용 + `localizedLabel` 직접 사용.

### C2 영향 호출처 (예상)
- `Sources/Panels/BrainObjectInspector/BrainObjectInspectorAtoms.swift` (StatusGlyph 정의 + 자체 호출 + EditableGoalStatusPill)
- `Sources/Panels/BrainObjectInspector/EditableTaskPills.swift`
- `Sources/VerticalTabsSidebar/Tasks/TaskListRow.swift`
- `Sources/VerticalTabsSidebar/Tasks/Pickers/TaskStatusPicker.swift`
- `Sources/VerticalTabsSidebar/Tasks/Pickers/TaskFilterValuePicker.swift`
- 신규 `Sources/VerticalTabsSidebar/Goals/GoalStatusRow` 호출부

### C3. Frontmatter scalar write helper (사이드바 전용)
- 현 상태: `TaskListView.applyFrontmatter(task:key:value:)` 가 disk read → `BrainFrontmatterWriter.setScalar` → atomic write 패턴을 인스턴스 메소드로 들고 있음.
- 변경: `BrainFrontmatterWriter` 에 static 메소드 `applyScalar(at filePath: String, key: String, value: String?)` 추가.
- `TaskListView.applyFrontmatter` 는 헬퍼 직접 호출로 교체. Goals 의 `writeStatus` 도 동일 헬퍼.

**참고: `MarkdownPanel.updateFrontmatter` 와는 흐름이 달라서 통합 대상 아님.**

| | TaskListView (sidebar) / Goals (sidebar) | MarkdownPanel (editor) |
|---|---|---|
| in-memory state | 없음 (disk 가 진실) | live `content` 변수가 진실 |
| disk read | 매번 필요 | 안 함 (snapshot 사용) |
| post-write | watcher 가 store reparse | optimistic `self.content` 갱신 + `scheduleParse()` |
| 에러 처리 | `try?` (조용히 실패) | do/try/catch + `NSLog` |

두 흐름이 다르기 때문에 C3 헬퍼는 사이드바 두 곳 (Tasks/Goals) 에만 적용. `MarkdownPanel.updateFrontmatter` 는 in-memory snapshot 기준이라 그대로 둔다 — 거기서 공유되는 건 이미 `BrainFrontmatterWriter.setScalar` (문자열 변환) 한 단계뿐이고 그건 이 작업 전부터 공용.

BrainObjectInspector 의 editable pill 들 (`EditableTaskPills`, `EditableGoalStatusPill`, …) 은 자체적으로 file write 하지 않고 `onChange` 클로저로 부모에 위임 → 최종 호출처는 `MarkdownPanel.updateFrontmatter`. 즉 inspector 는 C3 의 직접 호출처가 아니다.

### C4. Sidebar row chrome
- 디자인 결정: **Goal row 도 Task 와 동일한 chrome** 사용 (좌측 2pt accent bar + selection background tint + hover tint). 본 작업에서 통일.
- 신규 modifier `SidebarRowChrome` (`Sources/VerticalTabsSidebar/Shared/SidebarRowChrome.swift`):
  ```
  struct SidebarRowChrome: ViewModifier {
      let isSelected: Bool
      let isHovered: Bool
      func body(content: Content) -> some View {
          content
              .background(rowBackground)               // selected: accent.0.18, hover: bgHover, else: clear
              .overlay(alignment: .leading) {
                  if isSelected {
                      Rectangle().fill(BVColor.accent).frame(width: 2)
                  }
              }
              .contentShape(Rectangle())
      }
  }
  ```
- padding / height 는 row 종류마다 다르므로 (outline 은 depth × indent, cadence/status 는 flush) 호출자가 본인 책임. modifier 는 background+overlay+contentShape 3가지만 묶음.
- 적용: `TaskListRow` 외곽, `GoalOutlineRow`, `GoalCadenceRow`, `GoalStatusRow` 4곳. 기존 `GoalFlatRowChrome` 삭제.
- 클릭 hookup 도 통일: Task 는 `.onTapGesture`, Goal 은 `Button(action:)` 안에 wrap. 본 작업에선 Goal 도 **Task 방식 (외곽 `.onTapGesture`)** 으로 통일 — `Button` wrapper 가 buttonStyle 충돌 줄여줌.
- Hover state: 각 row 가 `@State var rowHover = false` 보유 + `.onHover { rowHover = $0 }`. Task 에서 이미 쓰던 패턴 그대로.

### C5. Status glyph hit-box modifier
- 신규 modifier `StatusGlyphHitBox` (`Sources/VerticalTabsSidebar/Shared/StatusGlyphHitBox.swift` 또는 C4 와 같은 파일에 합쳐도 됨):
  ```
  struct StatusGlyphHitBox: ViewModifier {
      let hover: Bool
      func body(content: Content) -> some View {
          content
              .frame(width: 14, height: 14)
              .scaleEffect(hover ? 1.08 : 1.0)
              .contentShape(Rectangle())
      }
  }
  ```
- 적용: `TaskListRow.statusButton`, `GoalStatusRow` 의 신규 status 버튼 2곳. 호출부 1줄로 축소.
- 14pt 크기 / 1.08 scale / Rectangle hit area 가 한 군데서 관리됨.

## 변경 사항 (모드별)

### 공통 — section header 교체
- `GoalCollapsibleHeader`, `GoalGroupHeader` 두 컴포넌트를 **삭제**하고 모든 모드에서 C1 의 `SidebarSectionHeader` 사용.
- 결과: 폰트·tracking·chevron 위치가 task 와 픽셀 단위로 일치.

### 구조 (Outline)
- `GoalOutlineRow` 의 트리 chevron + depth indent 는 본질이라 그대로.
- Row chrome → `SidebarRowChrome` (C4) 적용 (좌측 accent bar + hover tint).
- 루트 헤더 ("Goals · N") 만 `SidebarSectionHeader` (C1) 로 치환. 비-collapsible 호출 (`onToggle: {}`, `isCollapsed: false`).

### 주기 (Cadence)
1. 섹션 헤더 (DAILY/WEEKLY/MONTHLY/QUARTERLY) → `SidebarSectionHeader` (C1)
2. `GoalCadenceRow` 에서 `flatRowLeadingInset` 사용 제거 → 타이틀이 헤더와 같은 좌측 라인에 정렬
3. Row chrome → `SidebarRowChrome` (C4) 적용 (좌측 accent bar + hover tint 활성화). 클릭 hookup 을 `.onTapGesture` 로 통일.
4. Due pill 그대로 유지

### 상태 (Status)
1. 섹션 헤더 → `SidebarSectionHeader` (`BrainGoalStatus.label` 그대로 들어가서 ACTIVE / BLOCKED / DRAFT / COMPLETED / ARCHIVED 로 표시됨). C0 에서 추가된 unknown bucket 은 별도 헤더 "UNKNOWN".
2. `GoalStatusRow` 에서 `flatRowLeadingInset` 사용 제거
3. Row chrome → `SidebarRowChrome` (C4) 적용
4. **Status 글리프 추가 + 클릭 시 picker** — `TaskListRow.statusButton` 코드 패턴 1:1 재현 (C0 정책 통일로 Task 와 분기 모양 동일):
   - 좌측 status 버튼 + `.modifier(StatusGlyphHitBox(hover: statusHover))` (C5)
   - 분기 (C2 옵션 D 시그너처): `if let status = entry.status { StatusGlyph(shape: status.glyphShape) } else if entry.unrecognizedStatusRaw != nil { unknownGlyph } else { 점선 빈 원 }`
   - 탭 → `panelPopover` 에 `OptionPicker(current: entry.status, ordered: BrainGoalStatus.allCases, label: { $0.localizedLabel }, glyph: { StatusGlyph(shape: $0.glyphShape) }, onSelect: …)`
   - 선택 → 상위 `onChangeStatus(entry, newStatus)` 클로저
5. 우측 N/M milestone 분수는 그대로

## Status write-back 경로 (Task 와 1:1)

`GoalsListBody` 는 snapshot boundary 하단이라 store 참조 불가. 콜백은 컨테이너인 `GoalsListView` 에서 처리한다 — `TaskListView.writeStatus` 와 동일한 구조.

필요한 신규 코드 (실측 ~35라인):
- `GoalEntry.with(...)` — C0 에서 추가됨. TaskItem.with 와 동일 시그너처
- `GoalsListView.writeStatus(entry:newStatus:)`:
  ```
  store.replace(entry.with(status: .some(newStatus), unrecognizedStatusRaw: .some(nil)))
  BrainFrontmatterWriter.applyScalar(at: entry.absolutePath, key: "status", value: newStatus.rawValue)
  ```
  unrecognizedStatusRaw 도 같이 클리어 (Task 와 동일 패턴 — picker 로 선택했으니 schema 위반값은 사라짐).
  (C3 헬퍼 사용 — Task/Goal 양쪽 공통 경로)
- `GoalsListBody` → `GoalsListView` 로 콜백 라우팅: `onChangeStatus: (GoalEntry, BrainGoalStatus) -> Void` 한 줄 props 추가.

## 영향 파일 (총 12 변경, 신규 5)

| 파일 | 변경 |
|---|---|
| **신규** `Sources/VerticalTabsSidebar/Shared/SidebarSectionHeader.swift` | `TaskGroupHeader` 이동 + rename (C1) |
| **신규** `Sources/Panels/BrainObjectInspector/StatusGlyphShape.swift` | 시각 vocabulary enum 정의 (C2 옵션 D) |
| **신규** `Sources/VerticalTabsSidebar/Shared/SidebarRowChrome.swift` | row 외곽 chrome modifier (C4) |
| **신규** `Sources/VerticalTabsSidebar/Shared/StatusGlyphHitBox.swift` | status 글리프 hit-box modifier (C5) — 또는 C4 와 같은 파일 |
| **신규** (또는 enum 정의 파일에 extension) | `BrainTaskStatus.glyphShape`, `BrainGoalStatus.glyphShape`, `BrainGoalStatus.localizedLabel` extension (C2) |
| `Sources/VerticalTabsSidebar/Goals/GoalFrontmatterParser.swift` | unknown → `.draft` 흡수 제거 → `nil` 보존 + `unrecognizedStatusRaw` 추출 (C0) |
| `Sources/VerticalTabsSidebar/Goals/GoalEntry.swift` | `status: BrainGoalStatus?` (optional 화), `unrecognizedStatusRaw: String?` 필드 추가, `with(...)` 메소드 추가 (C0) |
| `Sources/VerticalTabsSidebar/Tasks/TaskGroupHeader.swift` | 삭제 (C1) |
| `Sources/VerticalTabsSidebar/Tasks/TaskListView.swift` | `TaskGroupHeader` → `SidebarSectionHeader` 호출 치환. `applyFrontmatter` → `BrainFrontmatterWriter.applyScalar(at:…)` 로 본문 교체 |
| `Sources/VerticalTabsSidebar/Tasks/TaskListRow.swift` | row 외곽 chrome 을 `SidebarRowChrome` (C4) 로 치환. status 버튼 chrome 을 `StatusGlyphHitBox` (C5) 로 치환. `StatusGlyph(status:)` 호출은 호환성 init 으로 그대로 두거나 `StatusGlyph(shape: status.glyphShape)` 로 정리 |
| `Sources/VerticalTabsSidebar/Tasks/Pickers/TaskStatusPicker.swift`, `TaskFilterValuePicker.swift` | `StatusGlyph(status:)` → `StatusGlyph(shape: $0.glyphShape)` (또는 호환 init 유지) |
| `Sources/Panels/BrainObjectInspector/BrainObjectInspectorAtoms.swift` | `StatusGlyph` 시그너처 변경 (shape 기반) + 호환 init. `private func glyphMapping`/`private func goalStatusLabel` 제거. `EditableGoalStatusPill` 이 `status.glyphShape` / `status.localizedLabel` 직접 사용. nil/unrecognized 분기 Task 와 정렬 (C0 영향) |
| `Sources/Panels/BrainObjectInspector/EditableTaskPills.swift` | `StatusGlyph(status:)` 호출부 정리 (호환 init 또는 shape 기반) |
| `Sources/Panels/BrainObjectInspector/BrainFrontmatterWriter.swift` | static `applyScalar(at:key:value:)` 추가 (C3) |
| `Sources/VerticalTabsSidebar/Goals/GoalRow.swift` | `GoalCollapsibleHeader`, `GoalGroupHeader`, `GoalFlatRowChrome` 삭제. 세 row 모두 `SidebarRowChrome` (C4) 적용. `GoalStatusRow` 에 status 글리프 버튼 (Task 와 동일 분기: status / unrecognized / nil, `StatusGlyph(shape: status.glyphShape)`) + `StatusGlyphHitBox` (C5) + popover 추가. `status == .completed` 비교 코드를 optional 정합 |
| `Sources/VerticalTabsSidebar/Goals/GoalsListView.swift` | 세 layout 의 section header 호출 → `SidebarSectionHeader`. `StatusLayout.bucketize` 가 nil/unrecognized 엔트리를 "UNKNOWN" bucket 으로 분리. `onChangeStatus` 콜백 props 추가. `GoalsListView` 에 `writeStatus` 추가 |
| `Sources/VerticalTabsSidebar/Goals/GoalsDesignTokens.swift` | `flatRowLeadingInset` 토큰 삭제 |

재사용 (변경 없음): `OptionPicker`, `panelPopover`.

도메인-신규 컴포넌트 (Goals 만의 새 시각 요소): **0개**. C2 옵션 D 로 시각/도메인 모델이 더 깔끔해짐 — `archived ≠ canceled` 같은 분기도 향후 자연스럽게 처리 가능 (별 issue 에서).

## 마이그레이션 순서

각 단계는 독립 commit 가능. 1 은 정책 변경 (Goal 데이터 모델), 2~6 은 행위 보존 리팩터 (Task 쪽만 손댐), 7~ 가 Goals 사이드바 UI 작업.

1. **C0** `GoalFrontmatterParser` 의 `?? .draft` 제거 + `unrecognizedStatusRaw` 추출 로직 추가. `GoalEntry.status` optional 화 + `unrecognizedStatusRaw` 필드 + `with(...)` 메소드. `EditableGoalStatusPill` 의 nil/unrecognized 분기 정렬. 의존 호출처 (status==.completed 등) optional 정합. **첫 번째 commit (Commit C0).**
2. **C3** `BrainFrontmatterWriter.applyScalar(at:key:value:)` 추가 → `TaskListView.applyFrontmatter` 본문을 헬퍼로 이전 + 호출부를 헬퍼 직접 호출로 교체 (행위 동일)
3. **C2** `StatusGlyphShape.swift` 신규 + `StatusGlyph` 시그너처 변경 (shape 기반) + 호환 init + `BrainTaskStatus.glyphShape` / `BrainGoalStatus.glyphShape` / `BrainGoalStatus.localizedLabel` extension. `glyphMapping` / `goalStatusLabel` private 함수 제거. `EditableGoalStatusPill` 이 `status.glyphShape` 직접 사용 (행위 동일 — glyph 5가지 모양은 그대로 매핑됨)
4. **C1** `SidebarSectionHeader.swift` 신규 + `TaskGroupHeader.swift` 삭제 + `TaskListView` 호출 치환 (행위 동일)
5. **C4** `SidebarRowChrome.swift` 신규 + `TaskListRow` 외곽 chrome 을 modifier 호출로 교체 (행위 동일 — Task 쪽에서 background/overlay/contentShape 코드만 modifier 로 이전)
6. **C5** `StatusGlyphHitBox.swift` 신규 + `TaskListRow.statusButton` 의 3줄 chrome 을 modifier 호출로 교체 (행위 동일)
7. `GoalsListView` 의 세 layout 헤더 호출 → `SidebarSectionHeader`
8. `flatRowLeadingInset` 제거 (토큰 + row 사용처)
9. `GoalOutlineRow` / `GoalCadenceRow` / `GoalStatusRow` 의 chrome 을 `SidebarRowChrome` 으로 통일 (`GoalFlatRowChrome` 삭제). 클릭 hookup 을 `.onTapGesture` 패턴으로 통일. `@State rowHover` 추가
10. `GoalStatusRow` 에 status 버튼 (Task 와 동일 3분기, `StatusGlyph(shape: status.glyphShape)` + `StatusGlyphHitBox` + `panelPopover`) + `onChangeStatus` 콜백 라우팅
11. `GoalsListView.StatusLayout.bucketize` 에 unknown (nil/unrecognized) bucket + UNKNOWN 섹션 헤더 추가
12. `GoalsListView.writeStatus` 구현 (status + unrecognizedStatusRaw 동시 클리어) + 콜백 연결
13. `GoalRow.swift` 의 죽은 `GoalCollapsibleHeader` / `GoalGroupHeader` / `GoalFlatRowChrome` 삭제
14. `./scripts/reload.sh --tag goals-task-align` 빌드 → 세 모드 시각 확인 + 상태 변경 동작 + hover/선택 막대 + 오타값 ? 표시 확인

## 확인 체크리스트 (수동 검증)

- [ ] 구조: "Goals · N" 헤더 폰트가 Tasks 섹션 헤더와 동일
- [ ] 주기: DAILY/WEEKLY/MONTHLY/QUARTERLY 헤더가 Tasks 스타일, 행 타이틀이 헤더 좌측 라인과 일치, due pill 정상
- [ ] 상태: 행 좌측 14×14 status 글리프가 task 와 동일 vocabulary 로 표시 (active=반원 채움, blocked=가로 막대, draft=링, completed=체크, archived=가로 막대 흑)
- [ ] 상태: 글리프 클릭 → picker → 선택 → 즉시 글리프 갱신 + 파일 frontmatter `status:` 변경됨
- [ ] **선택**: 세 모드 모두 행을 선택했을 때 좌측 2pt accent bar + 옅은 accent background tint 가 task 와 동일하게 표시
- [ ] **Hover**: 세 모드 모두 행 위에 마우스 올리면 회색 hover tint 가 task 와 동일하게 표시
- [ ] **C0 오타 시나리오**: 임의 goal 파일의 frontmatter 에 `status: actve` (오타) 적어두기 → 사이드바 상태 모드의 "UNKNOWN" 섹션에 ? glyph 로 표시 → picker 로 active 선택 시 ? 사라지고 frontmatter raw 도 정상화
- [ ] **C0 키 누락 시나리오**: `status:` 키 자체 없는 goal 파일 → 점선 빈 원 glyph 로 "UNKNOWN" 섹션에 표시
- [ ] archived 그룹 기본 접힘 유지 (`collapsedStatusSections = [.archived]` 그대로)
- [ ] 우상단 `chevron.up.chevron.down` collapse-all 동작 그대로
- [ ] **Task 회귀**: Tasks 사이드바의 선택/hover/status 변경이 본 작업 전후 동일 (C1/C3/C4/C5 가 Task 쪽도 건드리므로 회귀 점검 필수)
- [ ] **Inspector 회귀**: 골 파일 열어서 `EditableGoalStatusPill` 의 status 변경이 본 작업 전후 동일 (C0/C2 가 Inspector 도 건드림)

## 비결정 사항

- **Status 모드에서 archived 토글 위치/노출**: 기존 정책 유지(접힘 디폴트), 변경 안 함.
- **UNKNOWN 그룹 디폴트 접힘**: C0 으로 신설되는 UNKNOWN bucket 을 archived 처럼 디폴트 접힘으로 둘지, 펼쳐서 데이터 청소 affordance 를 키울지. **현재 결정**: 펼침 디폴트 (오타 발견 = 본 작업 목적).
- **`BrainGoalStatus.label` 의 case**: 현재 uppercase ("ACTIVE"). 신규 `localizedLabel` 은 sentence case ("Active"). label 을 sentence case 로 통일하고 header 가 `.uppercased()` 책임 (자연) — 본 작업에서 정리.

## 별 issue 로 떠놓을 항목

본 작업과 분리해서 별 issue / 별 PR 로 처리할 사안:

1. **Glyph 매핑이 lossy 한 부분**:
   - `archived` 와 `canceled` 가 같은 ▬ + 흑 모양으로 그려져 시각 구분 불가. 도메인 의미는 다름 (archived = 완료 후 정리 / canceled = 의도적 중단).
   - `draft` 와 `todo` / `backlog` 의 시각 통일도 점검 필요 (지금 draft → todo → `.open`, backlog → `.open`). 시각상 구분 불가하지만 의미 차이 있음.
   - 조치: `StatusGlyphShape` 에 case 추가 (`archivedBox` 같은 별도 도형) + 디자인 결정. 본 작업의 C2 옵션 D 가 이를 위한 기반이라 별 PR 작업이 가벼움.

2. **`BrainTaskStatus.legacy` 케이스 처리**:
   - `waiting`, `canceled` 가 enum 에 남아 picker 에서만 숨김. 데이터 마이그레이션 + enum 정리 가능성 검토.

3. **Vault file content cache (editor ↔ sidebar 통합)**:
   - 현재 `MarkdownPanel` 은 in-memory `content`, sidebar 는 disk read. 같은 파일이 동시에 열려있을 때 sidebar write 가 editor unsaved 변경과 충돌 가능.
   - 별 디자인 문서로 검토. 본 작업 5~10배 규모.
