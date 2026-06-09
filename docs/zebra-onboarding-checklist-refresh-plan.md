# Zebra 온보딩 체크리스트 Refresh 범위 축소 계획

## 요약

현재 온보딩 체크리스트는 진행표처럼 보이지만, 내부 동작은 매번 시스템 상태를 다시 진단하는 방식에 가깝다. state 파일 변경, vault/email 상태 동기화, 단계 실행 후 타이머 같은 이벤트가 발생하면 `refreshDetectedCompletion()`이 1-7단계를 다시 계산하고, 그 결과로 `completedStepIDs` 전체를 새로 만든다. 그래서 3단계 GBrain setup 중에 파일 watcher가 반응하면 2단계 runtime까지 다시 검사되고, runtime receipt나 executable/config 검증이 순간적으로 실패하면 이미 체크됐던 2단계가 false로 내려갈 수 있다.

구현 방향은 체크리스트를 "계속 재진단하는 건강검진표"가 아니라 "사용자가 완료한 단계를 안정적으로 보여주는 진행표"에 가깝게 바꾸는 것이다. watcher는 앱/스토어 생성 시 항상 켜두지 않고, Zebra 사이드바 또는 온보딩 부모 화면이 살아 있을 때만 켠다. 파일 변경에 반응하면 전체 1-7단계를 다시 계산하지 않고 변경된 단계만 좁게 갱신한다. 이미 완료된 이전 단계는 명확한 실패 기록이 있을 때만 내린다.

기억해야 할 핵심은 세 가지다. 첫째, 체크리스트 카드 자체는 `completedCount < totalCount` 결과에 따라 숨겨질 수 있으므로 watcher 기준으로 삼으면 안 된다. 기준은 카드가 아니라 카드를 담는 Zebra 사이드바/온보딩 부모 view 생명주기여야 한다. 둘째, 파일 변경 refresh는 변경된 단계만 갱신해야 한다. 3단계 state 파일 변경이 2단계 runtime 재검사를 유발하면 안 된다. 셋째, 완료된 이전 단계는 관련 없는 refresh 때마다 0부터 재채점하지 않는다. 다만 그 단계 자신의 state가 바뀌고 `receipt.complete == false`처럼 명시적 실패가 기록된 경우에는 해당 단계만 다시 평가해서 체크를 해제할 수 있다.

## 현재 문제

`ZebraOnboardingChecklistStore.refreshDetectedCompletion()`은 refresh가 일어날 때마다 runtime, gbrain, adapter, email 상태를 다시 읽고 `applyDetectedCompletion()`으로 넘긴다. `applyDetectedCompletion()`은 기존 완료 목록을 기반으로 갱신하지 않고 새 `Set<ZebraOnboardingChecklistStepID>`를 만든 뒤 `completedStepIDs`를 통째로 교체한다.

현재 흐름:

```text
[refresh 이벤트]
  -> [runtime 완료 여부 계산]
  -> [gbrain 완료 여부 계산]
  -> [adapter 완료 여부 계산]
  -> [email 완료 여부 계산]
  -> [completedStepIDs 전체 교체]
```

이 구조에서는 어떤 단계의 validator가 일시적으로 false를 반환해도 해당 단계가 바로 체크 해제된다. 특히 2단계 `.gbrainRuntime`은 완료 receipt가 있어도 다음 조건을 매번 다시 만족해야 한다.

- receipt가 있고 `complete == true`
- runtime id가 지원되는 값
- `executablePath`가 현재 executable file
- `keySource` 존재
- `checks.credentials == true`
- `checks.runtimeConfigCommand == true`
- `checks.llmCall == true`

3단계 agent/helper가 작업하면서 onboarding state 파일을 쓰면 file watcher가 refresh를 예약한다. 이 refresh는 3단계만 보지 않고 2단계까지 다시 본다. 그 순간 runtime state가 쓰는 중이거나 executable/config/credential 검증이 흔들리면 2단계 체크가 내려갈 수 있다.

## Refresh 발생 지점

현재 refresh는 다음 상황에서 일어난다.

- `ZebraOnboardingChecklistStore` 생성 시
- `syncExternalState(selectedVaultPath:emailConnected:)` 호출 시
- `beginLaunch(stepID:)` 후 120초 타이머가 끝날 때
- onboarding 관련 디렉터리 file watcher가 write/delete/rename/extend 이벤트를 감지했을 때
- background GBrain completion refresh가 끝났을 때

문제의 중심은 file watcher다. 3단계 state 파일 변경이 2단계 재검사까지 유발하기 때문이다.

## 목표

- 온보딩 체크리스트가 보이는 사용자 경험은 안정적인 진행표처럼 동작한다.
- 앱을 다시 열거나 온보딩 부모 화면에 진입하면 현재 상태를 한 번 복구한다.
- 화면이 살아 있는 동안 필요한 변경은 반영하되, 모든 파일 변경이 모든 단계를 다시 흔들지 않게 한다.
- 이미 완료된 이전 단계는 transient false 때문에 체크 해제하지 않는다.
- 명시적인 실패, reset, 선택 변경처럼 실제로 진행 상태를 되돌려야 하는 경우는 계속 반영한다.

## 구현 계획

### 1. Store init에서 watcher 자동 시작 제거

현재 store 초기화 중 `startCompletionFileWatching()`이 호출된다. 이를 제거하고 watcher start/stop을 명시 API로 바꾼다.

예상 API:

```swift
public func activateCompletionWatching()
public func deactivateCompletionWatching()
```

`activateCompletionWatching()`은 watcher를 시작하고 `refreshDetectedCompletion()`을 한 번 호출한다. 중복 호출되어도 watcher가 중복 설치되지 않게 idempotent하게 만든다.

`deactivateCompletionWatching()`은 pending work item을 취소하고 watcher source를 닫는다.

### 2. 부모 화면 생명주기에 watcher 연결

체크리스트 card의 `onAppear`가 아니라, Zebra 사이드바/온보딩 영역을 소유하는 부모 view의 `onAppear` / `onDisappear`에 연결한다.

원하는 흐름:

```text
[Zebra sidebar/onboarding parent appears]
  -> activateCompletionWatching()
  -> refreshDetectedCompletion()

[Checklist card hidden because all steps complete]
  -> parent is still alive
  -> watcher may remain active

[Zebra sidebar/onboarding parent disappears]
  -> deactivateCompletionWatching()
```

카드 자체를 기준으로 삼지 않는 이유는 카드 표시 여부가 완료 상태의 결과이기 때문이다. 모든 단계가 완료되어 카드가 숨겨진 상태에서 watcher까지 꺼지면, 이후 외부 상태 변화로 체크리스트가 다시 나타나야 하는 경우를 놓칠 수 있다.

### 3. File watcher refresh를 단계별 갱신으로 변경

file watcher가 살아 있는 동안에도 기존처럼 전체 refresh를 호출하지 않는다. watcher 설치 시 어떤 directory/file group이 어떤 step에 대응하는지 알 수 있게 만들고, 변경 이벤트가 들어오면 해당 step evaluator만 실행한다.

원하는 매핑:

```text
[gbrain-runtime-state.json 변경]
  -> 2단계 .gbrainRuntime만 평가

[gbrain-setup-state.json 변경]
  -> 3단계 .gbrain만 평가

[gbrain-adapter-state.json 변경]
  -> 4단계 .adapter만 평가

[agent-cli-state.json / agent-cli-events.jsonl 변경]
  -> 1단계 .agent만 평가

[email/preference/vault 상태 변경]
  -> 관련 단계만 평가
```

directory watcher만으로 정확한 파일명을 구분하기 어렵다면, 이벤트 발생 시 해당 directory에 연결된 step 후보만 재평가한다. 예를 들어 onboarding directory 변경은 `.agent`, `.gbrainRuntime`, `.gbrain`, `.adapter` 후보로 나누되, 각 step update는 기존 `completedStepIDs` 전체를 새로 만들지 않고 해당 step만 add/remove 한다.

### 4. 완료된 runtime 단계 latch 추가

`.gbrainRuntime`은 한 번 확실히 완료로 인정된 뒤에는 soft false로 바로 내려가지 않게 한다.

대략적인 정책:

```text
[이번 runtime result == true]
  -> .gbrainRuntime completed 유지/추가

[이번 runtime result == false]
  -> 이전에 .gbrainRuntime completed가 아니었음
     -> 미완료 유지

  -> 이전에 .gbrainRuntime completed였음
     -> hard false면 체크 제거
     -> soft false면 체크 유지
```

중요한 전제: 이 runtime 재평가는 아무 refresh 때나 실행하지 않는다. `.gbrainRuntime` 자체를 평가하는 경우는 전체 복구 refresh, 또는 `gbrain-runtime-state.json`처럼 runtime 단계 자신의 state가 변경된 경우다. 3단계 `gbrain-setup-state.json` 변경은 `.gbrainRuntime`을 재평가하지 않는다.

초기 hard/soft 분류:

- hard false: receipt가 명시적으로 `complete: false`인 경우, helper가 실패 receipt를 기록한 경우
- soft false: `missing_receipt`, `executable_missing`, `credential_source_missing`, `credentials_unverified`, `runtime_config_unverified`, `llm_call_unverified`처럼 파일 쓰기 타이밍이나 외부 환경 때문에 순간적으로 흔들릴 수 있는 경우

이 분류는 우선 runtime 단계에 명시적으로 적용한다. 단계별 refresh 구조가 들어가면 3단계 파일 변경이 2단계를 건드리지 않게 되지만, 앱 진입이나 vault 변경처럼 전체 복구성 refresh가 필요한 순간에는 runtime도 다시 평가될 수 있으므로 latch는 여전히 필요하다.

### 5. 전체 복구 refresh와 단계별 refresh를 분리

전체 복구 refresh는 계속 필요하다. 앱 시작, 온보딩 부모 화면 진입, selected vault 변경처럼 "현재 상태를 처음 맞춰야 하는" 순간에는 전체 단계를 평가한다.

반면 file watcher에 의한 refresh는 단계별로 좁힌다.

```text
[전체 복구 refresh]
  -> 앱 진입 / 부모 화면 appear / vault-email state sync
  -> 전체 단계 평가
  -> 완료된 이전 단계 latch 정책 적용

[watcher refresh]
  -> 파일 변경 이벤트
  -> 변경된 step만 평가
  -> completedStepIDs에서 해당 step만 update
```

이를 위해 `applyDetectedCompletion()`은 전체 set 교체 전용 함수로 두지 않고, 다음 두 경로로 나눈다.

- `refreshAllDetectedCompletion()`: 전체 복구용. 모든 evaluator를 실행하되 latch 정책을 적용한다.
- `refreshDetectedCompletion(for stepID:)`: watcher용. 특정 step만 평가하고 해당 step만 update한다.

예시:

```text
[gbrain-setup-state.json 변경]
  -> refreshDetectedCompletion(for: .gbrain)
  -> .gbrainRuntime은 재평가하지 않음

[gbrain-runtime-state.json 변경]
  -> refreshDetectedCompletion(for: .gbrainRuntime)
  -> runtime receipt가 complete false면 .gbrainRuntime 체크 해제 가능
```

## 테스트 계획

### Unit test

추가할 핵심 테스트:

```text
testCompletedRuntimeStepStaysCompletedDuringGBrainRefreshWhenRuntimeProbeIsTemporarilyUnavailable
testGBrainStateWatcherRefreshDoesNotReevaluateCompletedRuntimeStep
```

검증 흐름:

```text
[완료된 runtime receipt 작성]
  -> store refresh
  -> .gbrainRuntime 완료 확인

[3단계 beginLaunch]
  -> runtime executable을 잠깐 제거하거나 runtime completion이 soft false가 되도록 구성
  -> refreshDetectedCompletion()
  -> .gbrainRuntime 체크가 유지되는지 확인

[3단계 state 파일 변경 watcher 시뮬레이션]
  -> .gbrain step refresh만 실행
  -> .gbrainRuntime evaluator가 호출되지 않거나, runtime 상태가 바뀌지 않는지 확인
```

추가로 watcher API가 idempotent한지도 테스트한다.

- `activateCompletionWatching()`을 여러 번 호출해도 watcher가 중복 설치되지 않는다.
- `deactivateCompletionWatching()` 후 pending refresh가 store 상태를 흔들지 않는다.

### Build

코드 변경 후에는 Zebra Debug reload를 tagged build로 실행한다.

```bash
./scripts/reload.sh --tag onboarding-checklist-refresh
```

## 비목표

- 모든 단계의 completion validator를 새로 설계하지 않는다.
- GBrain setup helper의 receipt schema를 대폭 변경하지 않는다.
- 카드 UI 디자인을 바꾸지 않는다.

## 예상 결과

3단계 agent가 작업하면서 `gbrain-setup-state.json`을 자주 쓰더라도, 화면이 실제로 살아 있는 동안만 watcher가 반응한다. watcher refresh는 3단계만 갱신하므로 2단계 runtime을 다시 건드리지 않는다. 앱 진입이나 부모 화면 appear처럼 전체 복구 refresh가 필요한 순간에도 이미 완료된 2단계 runtime은 명시적 실패가 아닌 transient false 때문에 체크 해제되지 않는다. 사용자는 체크리스트를 "계속 흔들리는 진단 결과"가 아니라 "완료한 단계가 안정적으로 쌓이는 진행 상태"로 보게 된다.
