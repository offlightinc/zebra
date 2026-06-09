# Zebra GBrain Onboarding Verify Improvement Plan

[Source: GBrain Zebra onboarding troubleshooting discussion, 2026-06-09]

## Summary

Zebra GBrain onboarding의 Step 9 verify는 GBrain 설치가 실제로 끝났는지 확인하는 최종 gate다.
이번 Hermes 기반 설치에서는 실제 setup 작업 대부분이 진행됐지만, 최종 verify가 정상 CLI 경로로 끝까지 통과하지 못했다.

관찰된 실패는 두 가지다.

1. `gbrain autopilot`이 background에서 local PGLite를 잡고 있어 Step 9 verify가 `pglite_busy`로 실패했다.
2. autopilot을 내려도 실제 `gbrain sources current --json` 또는 `gbrain sources list --json`가 macOS/PGLite WASM runtime error로 실패했다.

중요한 점은 두 번째 실패의 의미다.

```text
sources probe command가 실패함
!= source가 실제로 등록되어 있지 않음
```

현재 verify가 이 둘을 충분히 분리하지 못하면, source가 실제로 존재할 수 있는 상황에서도 `source_not_registered`처럼 보인다.
이 문서의 핵심 목표는 source 등록 상태와 source probe command health를 분리해서, Step 9 verify가 정확한 실패 원인을 기록하고 제한된 조건에서 warning 기반 pass를 허용하게 만드는 것이다.

## Goals

1. local PGLite 환경에서 background autopilot과 verify가 lock 경합을 만들지 않게 한다.
2. source probe command crash와 실제 source 미등록 또는 mismatch를 구분한다.
3. Step 4에서 source가 실제로 검증된 기록이 있으면, Step 9에서 source probe만 runtime error로 실패했을 때 `verified_with_warnings`를 허용한다.
4. 실제 source mismatch는 warning pass로 통과시키지 않는다.
5. verify 때문에 autopilot을 멈췄다면, 원래 켜져 있던 경우 반드시 다시 켠다.
6. 기존 `complete` / `reasons` contract는 유지하고, 상세 진단 필드를 추가한다.

## Non-Goals

- source probe failure를 무조건 성공으로 간주하지 않는다.
- agent가 "등록했다"고 말한 기록만으로 warning pass하지 않는다.
- shim이 하드코딩한 `sources` 응답을 정상 검증 근거로 삼지 않는다.
- remote/thin-client 구성을 local PGLite autopilot 정책으로 다루지 않는다.
- Step 9 verify 실패를 숨기기 위해 `complete: true`만 조용히 쓰지 않는다.

## Core Invariants

다음 조건은 구현 순서와 무관하게 반드시 지켜야 한다.

```text
PGLite/WASM runtime error
-> source_not_registered 아님
-> source probe runtime/probe error
```

```text
actual source id mismatch 또는 target path mismatch
-> source_not_registered
-> warning pass 금지
```

```text
Step 9 warning pass
-> doctor 성공
-> target path 존재
-> source id 존재
-> Step 4의 실제 helper-run source verification 기록 존재
-> Step 4 기록의 source id/path가 현재 Step 9 target과 일치
-> 현재 source probe 실패가 runtime/probe error
-> 현재 source probe가 actual mismatch를 보고하지 않음
```

```text
autopilot restore
-> 원래 켜져 있었으면 다시 켬
-> 원래 꺼져 있었으면 켜지 않음
-> verify 성공/실패와 무관하게 restore 시도
-> restore 실패는 warning으로 기록
```

## Current Failure Mode

현재 Step 9 verify는 `doctor --json`뿐 아니라 source probe까지 성공해야 complete로 본다.

대략적인 흐름은 다음과 같다.

```text
run gbrain doctor --json
run gbrain sources current --json
run gbrain sources list --json

doctor ok + source probe verified
-> complete true

source probe mismatch/failure
-> source_not_registered 또는 incomplete
```

이 구조에서 `sources current/list`가 PGLite runtime bug로 죽으면, 실제 source가 등록되어 있더라도 verify가 source 상태를 확인하지 못한다.
이때 실패 원인을 `source_not_registered`로 뭉개면 디버깅이 어려워지고, 실제 설치 상태와 verify 결과가 어긋난다.

이번에 관찰된 runtime error 예시는 다음 계열이다.

```text
PGLite failed to initialize its WASM runtime.
Most common cause: the macOS 26.3 WASM bug
Original error: Aborted().
```

이 메시지는 source mismatch가 아니라 source probe runtime failure로 분류해야 한다.

## Source Probe Result Model

source probe 결과는 최소한 다음 상태를 구분한다.

```text
verified
mismatch
transient
error
```

의미:

- `verified`: expected source id와 target path가 `sources current/list`에서 확인됨.
- `mismatch`: command는 실행됐고, 결과가 expected source id/path와 다름.
- `transient`: lock contention처럼 retry 가능성이 높은 일시 실패.
- `error`: command crash, runtime error, JSON parse 불가 등 source 상태와 command health를 분리해야 하는 실패.

reason 예시:

```text
pglite_busy
pglite_wasm_runtime_error
source_probe_runtime_error
source_probe_timeout
source_not_registered
```

`source_not_registered`는 실제 mismatch 또는 missing source에만 쓴다.
PGLite WASM crash, timeout, command crash에는 쓰지 않는다.

## Probe Failure Classification

source probe command stderr/stdout 또는 error message를 보고 runtime/probe failure를 분류한다.

예상 분류 규칙:

```python
def probe_failure_reason(message):
    text = (message or "").lower()
    if "timed out waiting for pglite lock" in text:
        return "pglite_busy"
    if "pglite failed to initialize its wasm runtime" in text:
        return "pglite_wasm_runtime_error"
    if "aborted()" in text and "pglite" in text:
        return "pglite_wasm_runtime_error"
    return "source_probe_runtime_error"
```

주의할 점:

- JSON parse 실패도 command output이 runtime crash 메시지이면 `error`로 분류한다.
- command가 정상 JSON을 반환했고 source id/path가 다르면 `mismatch`로 분류한다.
- `mismatch`와 `error`는 verify 정책에서 완전히 다르게 취급한다.

## Step 4 Source Verification Evidence

Step 4 완료 시점에 source가 실제로 검증됐다면 state/receipt에 명확한 evidence를 남긴다.
이 기록은 Step 9 warning pass의 유일한 fallback 근거다.

예시:

```json
{
  "sourceVerification": {
    "sourceId": "brain",
    "targetPath": "/Users/hanwool/brain",
    "verifiedAt": "2026-06-09T00:00:00Z",
    "method": "sources_current_and_list",
    "gbrainExecutablePath": "/Users/hanwool/.bun/bin/gbrain",
    "gbrainVersion": "0.42.8"
  }
}
```

이 기록은 helper가 실제 source probe를 성공시킨 경우에만 쓴다.
agent report만으로 만들면 안 된다.

Step 9에서 이 기록을 사용할 때는 최소한 다음을 비교한다.

- `sourceId`
- normalized `targetPath`
- 가능하면 `gbrainExecutablePath` 또는 resolved executable provenance
- 가능하면 `gbrainVersion`

executable provenance는 이 문제의 본질은 아니지만, 이전 검증 기록이 현재 verify 대상과 같은 설치 맥락에서 나온 것인지 확인하는 데 도움이 된다.

## Step 9 Warning Pass Policy

Step 9 verify는 source probe runtime/probe error가 발생해도 다음 조건을 모두 만족하면 warning 기반 pass를 허용한다.

```text
doctorOk == true
targetPath exists
sourceId is present
previous sourceVerification exists
previous sourceVerification.sourceId == current sourceId
previous sourceVerification.targetPath == current targetPath
current sourceProbe.status == error or transient runtime/probe failure
current sourceProbe.status != mismatch
```

성공 결과 예:

```json
{
  "complete": true,
  "status": "verified_with_warnings",
  "reasons": [],
  "warnings": ["pglite_wasm_runtime_error"],
  "doctorOk": true,
  "sourceProbe": {
    "ok": false,
    "status": "error",
    "reason": "pglite_wasm_runtime_error",
    "sourcePreviouslyVerified": true
  }
}
```

반대로 다음 상황에서는 pass하면 안 된다.

- `doctor` 실패
- target path 없음
- source id 없음
- previous source verification 없음
- previous source verification의 source id/path가 현재 target과 다름
- current source probe가 actual mismatch를 보고함
- source probe 실패 reason이 unknown인데 source 상태를 판단할 근거가 없음

실패 결과 예:

```json
{
  "complete": false,
  "status": "failed",
  "reasons": ["source_probe_runtime_error"],
  "warnings": [],
  "doctorOk": true,
  "sourceProbe": {
    "ok": false,
    "status": "error",
    "reason": "pglite_wasm_runtime_error",
    "sourcePreviouslyVerified": false
  }
}
```

## Autopilot Quiesce Policy

local PGLite target에서는 Step 7 이후 launchd/autopilot이 PGLite lock을 잡고 있을 수 있다.
Step 9 verify는 필요한 경우 autopilot을 잠깐 멈추고, verify 후 원래 상태로 복구한다.

정책:

```text
if target is local PGLite:
    was_running = check autopilot running
    if was_running:
        stop autopilot
    try:
        run doctor/source probe verify
    finally:
        if was_running:
            restart autopilot
```

제약:

- local PGLite target에만 적용한다.
- remote/thin-client 구성에는 적용하지 않는다.
- 원래 running인 경우에만 restore한다.
- 원래 stopped인 경우 verify가 끝나도 start하지 않는다.
- stop/start/status command는 안정적인 GBrain command surface 또는 명확한 launchd label을 통해 실행한다.
- restore 실패는 verify 결과를 덮어쓰지 않고 warning에 남긴다.

receipt/debug payload 예:

```json
{
  "autopilot": {
    "pausedForVerify": true,
    "wasRunning": true,
    "restored": true
  }
}
```

restore 실패 시:

```json
{
  "warnings": ["autopilot_restart_failed"],
  "autopilot": {
    "pausedForVerify": true,
    "wasRunning": true,
    "restored": false
  }
}
```

## Verify Result Shape

기존 consumer와의 호환성을 위해 `complete`와 `reasons`는 유지한다.
새 필드는 상세 진단용으로 추가한다.

권장 shape:

```json
{
  "complete": true,
  "status": "verified_with_warnings",
  "reasons": [],
  "warnings": ["pglite_wasm_runtime_error"],
  "doctorOk": true,
  "sourceProbe": {
    "ok": false,
    "status": "error",
    "reason": "pglite_wasm_runtime_error",
    "sourcePreviouslyVerified": true
  },
  "autopilot": {
    "pausedForVerify": true,
    "wasRunning": true,
    "restored": true
  }
}
```

가능한 `status` 값:

```text
verified
verified_with_warnings
failed
```

`complete: true`는 `verified`와 `verified_with_warnings` 모두에서 가능하다.
UI/debug에서는 `verified_with_warnings`를 숨기지 말고 표시할 수 있어야 한다.

## Implementation Notes

구현 순서는 본질이 아니다.
다만 안전하게 진행하려면 다음 단위로 쪼갤 수 있다.

1. source probe command failure와 actual mismatch를 분리한다.
2. PGLite/WASM runtime error를 명시적으로 classify한다.
3. Step 4 source verification evidence를 receipt/state에 남긴다.
4. Step 9에서 strict warning pass 조건을 적용한다.
5. verify result에 `status`, `warnings`, `sourceProbe`, `autopilot` 진단 필드를 추가한다.
6. local PGLite target에 autopilot quiesce/restore를 붙인다.

각 단계는 독립적으로 테스트 가능해야 한다.
중요한 것은 구현 순서가 아니라 위의 Core Invariants를 깨지 않는 것이다.

## Test Scenarios

### Test 1: Normal Verify

조건:

- autopilot 꺼짐
- `doctor --json` 성공
- `sources current/list --json` 성공

기대:

- `complete: true`
- `status: "verified"`
- warnings 없음

### Test 2: Autopilot Running

조건:

- local PGLite target
- autopilot running
- verify 실행

기대:

- verify 전 autopilot stop
- verify 후 autopilot restore
- `autopilot.wasRunning: true`
- `autopilot.restored: true`

### Test 3: Source Probe WASM Runtime Error With Previous Verification

조건:

- `doctor --json` 성공
- `sources current/list --json`가 PGLite WASM runtime error로 실패
- Step 4 source verification record 존재
- record의 source id/path가 현재 Step 9 target과 일치

기대:

- `complete: true`
- `status: "verified_with_warnings"`
- warning에 `pglite_wasm_runtime_error`
- `source_not_registered` 없음

### Test 4: Source Probe WASM Runtime Error Without Previous Verification

조건:

- `doctor --json` 성공
- `sources current/list --json`가 PGLite WASM runtime error로 실패
- previous source verification 없음

기대:

- `complete: false`
- reason은 `source_probe_runtime_error` 또는 `pglite_wasm_runtime_error`
- `source_not_registered`로 뭉개지 않음

### Test 5: Actual Source Mismatch

조건:

- command는 정상 JSON 반환
- current source id가 expected source id와 다름
- 또는 list의 local path가 target path와 다름

기대:

- `complete: false`
- reason `source_not_registered`
- warning pass 금지

### Test 6: Autopilot Restore Failure

조건:

- verify 전 autopilot running
- stop 성공
- verify 수행
- restore 실패

기대:

- verify 결과는 doctor/source probe의 본 검증 결과를 따른다.
- warning에 `autopilot_restart_failed`
- `autopilot.restored: false`

### Test 7: Previous Verification Target Mismatch

조건:

- previous source verification 존재
- 하지만 source id 또는 target path가 현재 Step 9 target과 다름
- 현재 source probe는 runtime error

기대:

- `complete: false`
- warning pass 금지
- source verification mismatch를 알 수 있는 reason/debug detail 기록

## Final Direction Summary

전체 구현 방향은 단순하다.

Step 9 verify는 더 이상 `sources current/list` 실패를 곧바로 "source가 없다"로 해석하면 안 된다.
먼저 실패의 성격을 나눈다.

```text
command가 정상 실행됐고 결과가 다름
-> source_not_registered

command 자체가 PGLite/WASM/runtime 문제로 죽음
-> source_probe_runtime_error 또는 pglite_wasm_runtime_error
```

그리고 Step 4에서 이미 같은 source id와 target path가 실제 helper probe로 검증된 기록이 있으면, Step 9의 probe runtime error는 설치 실패가 아니라 검증 probe 실패로 본다.
이 경우 `complete: true`는 가능하지만 반드시 `verified_with_warnings`로 남긴다.

autopilot 문제는 별도로 다룬다.
local PGLite verify 중 lock 경합을 줄이기 위해 원래 켜져 있던 autopilot만 잠깐 멈추고, verify 후 반드시 복구한다.
복구 실패는 설치 검증 결과를 덮어쓰지 않고 warning으로 기록한다.

한 문장으로 요약하면:

```text
source의 실제 등록 상태와 source probe command의 실행 실패를 분리하고,
이미 검증된 source에 대해서만 runtime probe 실패를 warning으로 낮춰 Step 9를 통과시킨다.
```
