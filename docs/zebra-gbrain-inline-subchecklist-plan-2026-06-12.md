# Zebra GBrain 3단계 인라인 하위 체크리스트 계획

[Source: Codex/Zebra planning conversation, 2026-06-12]

## 배경

Zebra 온보딩 체크리스트의 3단계는 top-level 단계로는 하나의 `.gbrain` 단계다. 하지만 실제 GBrain setup은 `INSTALL_FOR_AGENTS.md`의 여러 `##` 섹션을 따라 진행되고, agent가 `zebra-gbrain-onboarding report`를 호출하면서 섹션별 진행 상태를 `gbrain-setup-state.json`에 기록한다.

현재 UI는 top-level 7단계만 보여준다.

```text
1 agent
2 gbrainRuntime
3 gbrain
4 adapter
5 email
6 ingest
7 goals
```

사용자가 원하는 변경은 3단계 자체를 여러 top-level 단계로 쪼개는 것이 아니다. 3단계가 현재 진행 중이거나 다시 시작해야 할 상태일 때, 기존 3단계 row 아래에 GBrain setup의 하위 섹션들을 인라인 체크리스트로 펼쳐 보여주는 것이다.

## 현재 코드 근거

관련 코드는 Zebra-owned 영역 안에 있다.

```text
Packages/ZebraVault/Sources/ZebraVault/AgentOnboarding/ZebraOnboardingChecklist.swift
Sources/Zebra/Sidebar/ZebraSidebarBody.swift
Packages/ZebraVault/Sources/ZebraVault/AgentOnboarding/ZebraGBrainOnboarding.swift
```

현재 top-level step 정의는 `ZebraOnboardingChecklistStore.steps`에 있다. `.gbrain`은 3번 하나로만 존재한다.

```swift
StepDefinition(id: .gbrain, number: 3, staleTimeout: 15 * 60)
```

현재 row UX는 `ZebraOnboardingChecklistRow`에 들어 있다.

```text
빈 체크박스
완료 체크박스
running spinner
hover 시 stop 버튼
Start / Restart 버튼
active row background
완료 row muted text + strikethrough
```

GBrain 실행은 `ZebraOnboardingChecklistCommand.launchPlan(for: .gbrain, ...)`가 만든다. 이 launch는 `ZebraGBrainOnboardingStore.prepareLaunch(...)`를 호출하고, `prepareLaunch`는 기존 state의 `progress.completedSections`, `progress.nextSection`, `progress.waitingForUser`를 읽어 setup packet에 반영한다.

즉 "중간에 멈춘 상태에서 다시 시작"하는 기능은 이미 parent `.gbrain` restart 흐름의 의미다. 새 UI는 이 흐름을 하위 체크리스트에서도 보이게 하는 것이며, 별도의 GBrain installer를 만드는 일이 아니다.

## 상태 Source Of Truth

하위 체크리스트의 source of truth는 `gbrain-setup-state.json`의 read-only projection이다.

```text
docsManifest.installForAgentsSections
  -> 표시할 하위 항목 목록

progress.completedSections
  -> checked 여부

progress.nextSection
  -> 지금 해야 할 하위 항목

progress.waitingForUser.section
  -> 사용자 입력 때문에 멈춘 하위 항목

receipt
  -> parent `.gbrain` 완료 여부
```

중요한 분리:

```text
하위 항목 checked
  = agent가 해당 INSTALL_FOR_AGENTS.md 섹션을 completed report로 기록함

parent `.gbrain` checked
  = GBrain receipt와 live/cached verification이 완료됨
```

하위 항목이 모두 checked처럼 보여도, 최종 verify receipt가 통과하지 않으면 parent `.gbrain`은 checked가 되면 안 된다.

## 표시 정책

3단계 row 아래에 하위 체크리스트를 인라인으로 펼친다.

펼침 조건 기본안:

```text
.gbrain이 active
OR .gbrain이 running
OR .gbrain state에 progress가 있음
OR .gbrain 하위 섹션 중 일부가 completed
```

`.gbrain`이 완료되고 다음 top-level 단계로 넘어간 뒤에는 기본적으로 접어도 된다. 다만 "완료된 하위 항목 확인"이 필요하면 hover 또는 debug UI가 아니라 일반 펼침 유지 여부를 별도로 결정한다.

하위 항목은 기본적으로 `docsManifest.installForAgentsSections`에 있는 setup 섹션을 표시한다. 이렇게 하면 원문이 8개든 9개든 UI가 문서 snapshot을 그대로 따라간다.

추가로 `INSTALL_FOR_AGENTS.md`의 Step 1 앞에는 Zebra UI-only preflight row를 하나 주입한다.

```text
GBrain repo 확인 및 클론
  -> INSTALL_FOR_AGENTS.md 문서를 수정해서 넣는 항목이 아님
  -> docsManifest section도 아님
  -> Zebra checklist projection에서만 외부 합성으로 앞에 붙이는 항목
```

이 row는 문서 섹션 목록과 함께 보여준다. 문서 manifest가 아직 없더라도 valid local source repo가 이미 있으면 Zebra UI projection이 그 repo의 `INSTALL_FOR_AGENTS.md`를 read-only로 읽어 섹션 목록을 만든다. 이 경우 source repo 확인 프롬프트에 멈춰 있는 동안 preflight row가 active/running이고, 문서 Step 1 이후 항목들은 pending으로 표시된다.

문서 manifest도 없고 valid local source repo도 없으면 preflight row 하나만 단독으로 보여주지 않는다. `0/1`처럼 wrapper 내부 준비 상태만 노출되어 사용자가 실제 하위 흐름을 볼 수 없기 때문이다.

각 하위 row 상태:

```text
completedSections에 포함됨
  -> checked

nextSection 또는 waitingForUser.section과 일치함
  -> active/actionable

그 외 미완료 섹션
  -> unchecked pending
```

사용자가 명확히 말한 정책:

```text
미래 항목은 지금처럼 check false로 두면 된다.
당장 시작해야 할 단계만 재시작할 수 있으면 된다.
```

## 재시작 정책

하위 항목별로 완전히 독립된 executor를 만들지 않는다. 하지만 현재 해야 할 하위 항목에는 action affordance를 둘 수 있다.

허용되는 버튼:

```text
현재 nextSection 또는 waitingForUser.section인 하위 항목의 시작하기/다시 시작
```

그 버튼이 하는 일:

```text
onStartStep(.gbrain)
  -> 기존 parent `.gbrain` launchPlan 생성
  -> prepareLaunch가 completedSections/nextSection/waitingForUser를 setup packet에 주입
  -> 새 terminal agent가 현재 state에서 이어서 진행
```

하지 말아야 할 일:

```text
특정 미래 섹션을 강제로 nextSection처럼 실행하는 별도 prompt 생성
completedSections를 UI에서 임의로 바꾸기
helper state를 UI에서 직접 수정하기
Step 4 전용, Step 9 전용 같은 독립 launch path 만들기
```

이유는 helper가 installer가 아니라 기록/검증 ledger이기 때문이다. 설치 판단과 명령 실행은 agent가 하고, helper는 `report`, `status`, `verify`로 상태 기록과 guard를 담당한다. 따라서 UI는 "현재 state 기준으로 이어하기"를 호출해야지, state machine보다 앞서서 임의 점프를 약속하면 안 된다.

다만 이번 대화에서 정리된 의도는 임의 점프가 아니다. 의도는 "현재 멈춘 하위 항목에서 이어 시작"이다. 이 흐름은 기존 parent restart와 같은 계약이므로 구현해도 된다.

## 공통화 계획

기존 top-level row UX 대부분을 하위 row에서도 재사용한다. 복붙 대신 작은 primitive로 분리한다.

추천 분리:

```text
ChecklistStatusIndicator
  - empty
  - completed
  - running
  - stop-on-hover

ChecklistStartButton
  - Start / Restart label
  - 동일한 accent fill
  - 동일 accessibility id 패턴

ChecklistRowChrome
  - active/hover background
  - padding
  - minimum height

ChecklistTitleStyle
  - completed muted + strikethrough
  - pending/active foreground
```

top-level row와 substep row는 같은 primitive를 쓰되 크기와 indentation만 다르게 둔다.

하위 row 전용 차이:

```text
number는 문서 section title에 이미 들어 있으므로 별도 top-level 숫자를 다시 붙이지 않아도 된다.
좌측에는 세로 guide line 또는 indent를 둔다.
체크박스 크기는 기존 row보다 같거나 약간 작게 둔다.
action button은 active 하위 항목에만 둔다.
```

## Spinner 정책

사용자는 spinner를 하위 체크리스트에 넣을지 아직 확신하지 않았다. 따라서 구현은 공통 primitive가 running 상태를 지원하게 만들되, 실제 표시 정책은 작게 시작한다.

권장 기본안:

```text
parent `.gbrain` row
  -> 기존처럼 runningStepID == .gbrain이면 spinner 표시

현재 active substep
  -> parent가 running 중이면 active highlight만 표시하거나 작은 spinner를 표시할 수 있음
  -> parent가 running 중이 아니면 Start/Restart 버튼 표시

미래 substep
  -> unchecked pending, spinner 없음
```

최종 디자인 선택:

```text
A. parent row에만 spinner
B. parent row + 현재 substep 둘 다 spinner
C. parent row는 running 상태만 유지하고, 실제 spinner는 현재 substep에만 표시
```

첫 구현은 A 또는 B가 안전하다. C는 기존 top-level UX를 더 많이 바꾸므로 나중에 시각 QA 후 결정한다.

## 상태 Projection API 계획

`ZebraGBrainOnboardingStore`에 read-only API를 추가한다.

예상 shape:

```swift
struct ZebraGBrainOnboardingSectionSnapshot: Equatable, Identifiable {
    let id: String
    let title: String
    let isCompleted: Bool
    let isActive: Bool
    let isWaitingForUser: Bool
    let isRunning: Bool
    let showsStart: Bool
    let wasStartedBefore: Bool
}
```

`ZebraOnboardingChecklistStepSnapshot`에는 optional 하위 항목을 붙인다.

```swift
let substeps: [ZebraGBrainOnboardingSectionSnapshot]
```

또는 `.gbrain` 전용이면 별도 property 이름을 더 명확히 둔다.

```swift
let gbrainSubsteps: [ZebraGBrainOnboardingSectionSnapshot]
```

상태 계산:

```text
sections = state.docsManifest.installForAgentsSections
if sections is empty and valid local source repo exists:
  sections = parse(sourceRepo/INSTALL_FOR_AGENTS.md)
preflight = "GBrain repo 확인 및 클론"
completed = Set(state.progress.completedSections)
waitingSection = state.progress.waitingForUser.section
sourcePrepared = state.activeGBrainBinding exists OR state.docsManifest exists
activeTitle = sourcePrepared ? (waitingSection ?? state.progress.nextSection) : nil

if sections is empty:
  return []

emit preflight as:
  completed = sourcePrepared
  active = !sourcePrepared
  running = parent .gbrain is running AND !sourcePrepared

for section in sections:
  isCompleted = completed contains section.title
  isActive = normalized(section.title) == normalized(activeTitle)
  showsStart = sourcePrepared AND parent .gbrain is first incomplete AND !running AND isActive
```

section title 비교는 원문 title이 거의 그대로 저장되므로 우선 exact match를 쓰되, legacy state나 agent report 차이를 고려해 normalized title fallback을 둔다.

## Source Onboarding 하위 row 확장

2026-07-02 기준으로 같은 공통 `substeps` projection은 5단계 Source Onboarding에도 쓰인다. Source Onboarding은 GBrain 문서 섹션이 아니라 `source-onboarding-state.json`의 source row를 표시한다.

Source row의 source of truth:

```text
progress.normalizedSourceList
  -> 표시 순서의 기본값

progress.sourceRows
  -> Gmail, Obsidian 같은 source별 상태

progress.activeSourceID
  -> 현재 이어서 실행해야 하는 source

progress.sourceConfirmation.status
  -> source별 시작 버튼을 보여주기 전 confirmation gate
```

상태 계산:

```text
orderedSourceIDs = normalizedSourceList + extra sourceRows sorted by id
if sourceConfirmation.status != confirmed:
  activeSourceID = nil
else if progress.activeSourceID points at a non-terminal row:
  activeSourceID = progress.activeSourceID
else:
  activeSourceID = first row whose status is not checked/skipped

for source row:
  completed = status == checked
  skipped = status == skipped
  active = row.id == activeSourceID
  running = parent .sourceOnboarding is running AND active
  showsStart = parent .sourceOnboarding is first incomplete AND !running AND active
  wasStartedBefore = playbookStepID exists OR status is running/attention
```

이 버튼은 source별 독립 executor를 새로 만드는 것이 아니다. active source row의 Start/Restart는 기존 parent `.sourceOnboarding` launch를 호출하고, helper가 저장한 `activeSourceID`/`playbookStepID` 기준으로 이어 진행한다.

Stop도 현재 구조에서는 row별 process kill이 아니라 `.sourceOnboarding`으로 등록된 터미널 세션에 Ctrl-C를 보내는 parent 세션 중지다. Gmail만 중지, Obsidian만 중지 같은 source별 프로세스 제어가 필요하면 substep id를 action callback에 포함하는 별도 설계가 필요하다.

## Localization

새 UI 문자열은 모두 `Resources/Localizable.xcstrings`의 Zebra append block에 추가한다.

필요할 수 있는 key:

```text
brain.onboarding.checklist.substep.continue
brain.onboarding.checklist.substep.waiting
brain.onboarding.checklist.substep.current
```

다만 화면 안에 설명 문장을 추가하지 않는 방향이므로, 실제 visible string은 기존 `Start`, `Restart`를 재사용하는 것이 가장 좋다. tooltip/help가 필요할 때만 새 string을 추가한다.

## Color / UI 정책

ZebraVault 신규 UI이므로 neutral chrome은 `BVColor` semantic token을 사용한다.

```text
background -> BVColor.bgElev / bgHover / bgFloating
text -> BVColor.fg / fgMute / fgFaint
border -> BVColor.border / borderStrong
shadow -> BVColor.shadow
```

고정 hue는 기존 checklist accent처럼 의미 색상에 한정한다.

카드 안에 또 다른 카드처럼 보이는 중첩 card를 만들지 않는다. 하위 체크리스트는 parent row 아래의 inline indentation/guide line으로 표현한다.

## 테스트 계획

가짜 source text나 grep 테스트가 아니라 runtime state projection을 테스트한다.

추가할 테스트:

```text
ZebraGBrainOnboardingStoreTests
  - docsManifest sections + completedSections를 읽어 substep snapshots를 만든다
  - docsManifest sections가 있으면 UI-only preflight row를 Step 1 앞에 붙인다
  - docsManifest sections가 없어도 valid recommended source repo가 있으면 그 `INSTALL_FOR_AGENTS.md`로 pending substeps를 만든다
  - docsManifest sections와 valid source repo가 모두 없으면 preflight row도 단독으로 표시하지 않는다
  - completed section은 checked
  - nextSection은 active
  - waitingForUser.section이 있으면 waiting section이 active를 이긴다
  - docsManifest가 없으면 substeps는 빈 배열

ZebraOnboardingChecklistStoreTests
  - `.gbrain` snapshot에만 substeps가 붙는다
  - active substep의 action은 parent `.gbrain` restart 조건과 동일하다
  - 미래 substep은 unchecked이고 showsStart false
```

UI snapshot 테스트가 없으면 모델 projection 테스트만 우선 추가한다. SwiftUI 내부 구현 shape를 문자열로 검사하는 테스트는 추가하지 않는다.

## 구현 순서

1. `ZebraGBrainOnboardingStore`에 cached state 기반 section snapshot projection 추가.
2. `ZebraOnboardingChecklistStepSnapshot`에 `.gbrain` 하위 snapshot 추가.
3. 기존 row 내부 요소를 reusable primitive로 분리.
4. `.gbrain` row 아래에 inline substep list 렌더링.
5. active substep의 Start/Restart action이 `onStartStep(.gbrain)`를 호출하도록 연결.
6. localization key가 필요한 경우 `Resources/Localizable.xcstrings` Zebra append block에 추가.
7. focused unit tests 추가.
8. 코드 변경 후 `./scripts/reload.sh --tag <tag>`로 Debug build 검증.

## 결정된 내용

이번 대화에서 결정된 내용:

```text
3단계는 top-level step 하나로 유지한다.
3단계 아래에 하위 체크리스트를 인라인으로 표시한다.
하위 항목은 Zebra UI-only preflight row + GBrain docs manifest의 setup section 목록을 따른다.
preflight row는 INSTALL_FOR_AGENTS.md를 건드리지 않고 checklist projection에서 외부 주입한다.
preflight row는 docs manifest section 또는 valid source repo에서 읽은 section들과 함께 있을 때만 표시하고, 단독 row로는 표시하지 않는다.
완료된 하위 항목은 checked로 표시한다.
미래 하위 항목은 unchecked pending으로만 둔다.
현재 해야 할 하위 항목만 시작하기/다시 시작 affordance를 갖는다.
그 action은 section-specific executor가 아니라 기존 `.gbrain` 이어하기 launch의 별칭이다.
기존 checklist row UX와 로직은 최대한 공통화한다.
```

## 아직 결정할 내용

구현 전에 확인할 내용:

```text
spinner를 parent row에만 둘지, 현재 substep에도 둘지
.gbrain parent 완료 후에도 substeps를 펼쳐둘지
하위 section title을 원문 그대로 보여줄지, "Step N:" 접두를 줄여 보여줄지
waitingForUser 상태를 visible text로 보여줄지, active style/tooltip만 둘지
```

권장 기본값:

```text
spinner는 parent row 유지, substep은 active highlight 중심
parent 완료 후에는 접기
section title은 원문 그대로 표시
waitingForUser는 별도 설명 문구 없이 active/action 상태로만 표현
```

## 전반적인 흐름 요약

전체 흐름은 다음과 같다.

```text
사용자가 Zebra 온보딩 체크리스트를 봄
  -> top-level 3단계 `.gbrain`이 active/running/progress 있음
  -> 3단계 row 아래에 GBrain 문서 section들이 인라인으로 펼쳐짐

Zebra가 gbrain-setup-state.json을 읽음
  -> docsManifest.installForAgentsSections로 문서 기반 하위 항목 목록 구성
  -> Zebra UI-only preflight row를 그 목록 앞에 주입
  -> progress.completedSections로 checked 표시
  -> progress.nextSection 또는 waitingForUser.section으로 현재 해야 할 항목 표시

사용자가 현재 하위 항목의 시작하기/다시 시작을 누름
  -> UI는 특정 section 전용 script를 만들지 않음
  -> 기존 onStartStep(.gbrain)을 호출
  -> prepareLaunch가 기존 completedSections/nextSection/waitingForUser를 setup packet에 넣음
  -> 새 terminal agent가 그 state를 읽고 이어서 진행

agent가 작업하면서 report 호출
  -> helper가 completedSections, nextSection, waitingForUser를 갱신
  -> checklist watcher가 state 변경을 감지
  -> 하위 체크리스트가 checked/active 상태를 업데이트

마지막 verify가 통과함
  -> receipt가 complete로 기록됨
  -> parent `.gbrain` top-level row가 checked 됨
  -> 이후 4단계 adapter로 진행
```

이 계획은 "하위 항목을 독립 설치 단위로 만들자"가 아니다. 기존 GBrain setup ledger와 restart 계약을 유지하면서, 지금 숨겨져 있던 `INSTALL_FOR_AGENTS.md` 섹션 진행 상태를 3단계 row 아래에 보여주는 UI/UX 변경이다.
