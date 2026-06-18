# Zebra GBrain onboarding wrapper rename plan

[Source: Codex/Zebra planning validation, 2026-06-18]

## 요약

Zebra GBrain onboarding은 더 이상 `gbrain` 이름의 PATH wrapper를 만들지 않는다.

핵심 원칙은 다음이다.

```text
`gbrain`
-> 실제 user-visible GBrain CLI만 의미한다.

Zebra 대리 실행
-> `zebra-gbrain-onboarding run-gbrain -- ...`가 담당한다.

Step 1 완료 검증
-> 실제 user-visible `gbrain --version`만 인정한다.
```

현재 Zebra는 onboarding helper dir을 PATH 앞에 넣고, 그 안에 `gbrain` wrapper를 생성한다. 이 때문에 Step 1에서 `which gbrain`이 실제 설치된 `~/.bun/bin/gbrain`이 아니라 Zebra wrapper를 잡을 수 있다. 실제 테스트에서도 `bun install -g .`가 `~/.bun/bin/gbrain`을 만들지 않았는데 wrapper 때문에 `gbrain --version` 검증이 헷갈렸다.

따라서 `bin/gbrain` wrapper는 제거하고, 같은 active source repo 실행 기능은 helper subcommand로 옮긴다.

## 결정

`Packages/ZebraVault/Sources/ZebraVault/AgentOnboarding/ZebraGBrainOnboarding.swift`에서 `installHelperScript()`는 다음만 설치한다.

```text
bin/zebra-gbrain-onboarding
bin/launchctl
```

`bin/gbrain`은 생성하지 않는다. `launchctl` wrapper는 이번 변경 범위에서 유지한다. `launchctl` wrapper는 recurring jobs / scheduler 설치 차단을 위한 별도 guard이고, `gbrain` 이름 혼동 문제와 분리된다.

새 helper command는 다음 형태다.

```bash
zebra-gbrain-onboarding run-gbrain -- <args>
```

예:

```bash
zebra-gbrain-onboarding run-gbrain -- --version
zebra-gbrain-onboarding run-gbrain -- autopilot --install --repo ~/brain
```

## run-gbrain 실행 규칙

`run-gbrain`은 active source repo만 대상으로 대리 실행한다. 실행 후보 순서는 다음이다.

```text
1. <active-source-repo>/node_modules/.bin/gbrain
2. <active-source-repo>/bin/gbrain
3. bun <active-source-repo>/src/cli.ts
```

임의 PATH의 `gbrain`으로 fallback하지 않는다. 이유는 `run-gbrain`의 목적이 “사용자 shell에 설치된 CLI 찾기”가 아니라 “Zebra가 확정한 active source repo의 CLI를 명시적으로 실행하기”이기 때문이다.

active source repo가 없거나 위 후보가 모두 없으면 non-zero로 실패한다. `src/cli.ts` fallback은 기존 wrapper와 동일한 개발용 대리 실행 경로로 유지한다.

## Step 1 설치 검증

Step 1 prompt와 guard는 `run-gbrain -- --version` 또는 `bun src/cli.ts --version` 성공을 완료 검증으로 인정하면 안 된다.

Step 1의 완료 조건은 실제 user-visible command가 되는 `gbrain --version` 성공이다. active source repo가 설정된 상태에서는 `global_gbrain_executable(state)` 경로가 이 의도와 맞다. 이 함수는 active source repo 내부의 `node_modules/.bin/gbrain` / `bin/gbrain`을 제외하고 PATH에서 실제 외부 `gbrain`을 찾는다.

따라서 prompt는 다음 의미를 유지해야 한다.

```text
recommended ~/gbrain source repo
-> bun install
-> bun install -g .
-> gbrain --version

custom source repo
-> bun install
-> bun link
-> gbrain --version
```

그리고 다음을 명시해야 한다.

```text
`zebra-gbrain-onboarding run-gbrain -- --version` 또는 `bun src/cli.ts --version`은
Step 1 완료 검증이 아니다.
```

기존 prompt의 “Zebra's PATH-provided `gbrain` wrapper” 표현은 wrapper 제거 후 부정확해지므로 `run-gbrain` / source-local 실행 검증을 Step 1 완료로 쓰지 말라는 문장으로 바꾼다.

## gbrain_executable 정리

`gbrain_executable()`은 내부 guard와 live verification에서 사용할 GBrain 실행 파일을 찾는다. Step 3 이후의 doctor/source/search/import 검증은 반드시 user-visible global CLI만 사용할 필요는 없다. active source repo의 local CLI를 우선 사용하는 현재 방향은 유지한다.

다만 Zebra wrapper fallback은 제거해야 한다.

현재 제거 대상:

```text
wrapper = gbrain_wrapper_path()
if os.access(wrapper, os.X_OK):
    return wrapper
```

유지할 후보:

```text
1. active source repo local CLI
2. PATH의 실제 gbrain
3. ~/.gbrain-profiles/*/gbrain-*
```

`gbrain_wrapper_path()`는 wrapper 제거 뒤에도 `path_gbrain_executable()` / `global_gbrain_executable()`에서 “과거 helper dir의 gbrain을 제외”하는 용도로 남길 수 있다. 실제 파일을 생성하지 않는 한 문제는 없다.

## Recurring Jobs / autopilot guard

기존 `gbrain` wrapper가 담당하던 autopilot install 차단은 `run-gbrain`으로 옮긴다.

차단 조건:

```text
command: run-gbrain -- autopilot --install ...
state: recurring_jobs_decision != autopilot_install
env: ZEBRA_GBRAIN_ALLOW_RECURRING_JOBS_INSTALL != 1
```

결과:

```text
exit 78
stderr에 recurring_jobs_decision=autopilot_install 필요 메시지 출력
```

승인 후에는 같은 명령을 active source repo CLI로 전달한다.

Step 7 prompt는 승인 후 실행 명령을 다음처럼 명시해야 한다.

```bash
zebra-gbrain-onboarding run-gbrain -- autopilot --install --repo <brain repo path>
```

흐름은 다음이다.

```text
1. report waiting_for_user --reason recurring_jobs_decision
2. user chooses autopilot_install
3. report started --recurring-jobs-decision autopilot_install
4. zebra-gbrain-onboarding check-launchd-bun-path
5. 필요하면 repair-launchd-bun-path 후 check 재실행
6. zebra-gbrain-onboarding run-gbrain -- autopilot --install ...
7. report completed --recurring-jobs-decision autopilot_install
```

`platform_scheduler_install`의 `launchctl` guard는 이번 변경에서 그대로 유지한다.

## 테스트 변경

`Packages/ZebraVault/Tests/ZebraVaultTests/ZebraGBrainOnboardingStoreTests.swift`에서 기존 wrapper 테스트는 `run-gbrain` 테스트로 바꾼다.

변경/추가할 테스트:

```text
helper install does not create bin/gbrain
run-gbrain -- --version forwards to active source CLI
run-gbrain prefers node_modules/.bin/gbrain over bin/gbrain
run-gbrain uses bin/gbrain when node_modules/.bin/gbrain is missing
run-gbrain falls back to bun src/cli.ts when no built binary exists
run-gbrain does not fallback to arbitrary PATH gbrain
run-gbrain autopilot --install exits 78 before autopilot_install approval
run-gbrain autopilot --install forwards after autopilot_install approval
Step 1 completed report fails without user-visible gbrain
Step 1 completed report succeeds with global/linked user-visible gbrain
Step 7 prompt mentions zebra-gbrain-onboarding run-gbrain -- autopilot --install
```

기존 의도 유지:

```text
Step 1 completed report는 wrapper/source-local CLI가 성공해도 통과하지 않는다.
실제 global/linked `gbrain --version`이 성공해야 통과한다.
```

기존 `testLaunchctlWrapperBlocksPersistentStartUntilRecurringJobsDecision` 계열은 유지한다. 이번 변경은 `gbrain` 이름의 wrapper 제거가 목적이지 launchd persistent command guard 제거가 아니다.

## 완료 기준

에이전트는 아래 항목을 직접 확인한 뒤에만 작업을 완료로 보고한다.

### 구현 완료 기준

```text
1. installHelperScript()가 bin/gbrain을 만들지 않는다.
2. gbrainWrapperScript 상수와 그 write/setAttributes 경로가 제거되어 있다.
3. zebra-gbrain-onboarding usage와 command dispatch에 run-gbrain이 포함되어 있다.
4. run-gbrain -- <args>는 active source repo를 읽고 다음 순서로만 실행한다.
   a. node_modules/.bin/gbrain
   b. bin/gbrain
   c. bun src/cli.ts
5. run-gbrain은 임의 PATH gbrain으로 fallback하지 않는다.
6. run-gbrain -- autopilot --install ...은 recurring_jobs_decision=autopilot_install 승인 전 exit 78로 차단한다.
7. 승인 후 run-gbrain -- autopilot --install ...은 active source repo CLI로 인자를 그대로 전달한다.
8. gbrain_executable()에서 Zebra wrapper fallback이 제거되어 있다.
9. Step 1 install prompt는 run-gbrain / bun src/cli.ts 성공을 완료 검증으로 인정하지 말라고 안내한다.
10. Step 7 recurring jobs prompt는 autopilot install 명령을 zebra-gbrain-onboarding run-gbrain -- autopilot --install ... 형태로 안내한다.
11. launchctl wrapper와 platform_scheduler_install guard는 유지되어 있다.
12. cmux upstream 파일은 수정하지 않는다.
```

### 테스트 완료 기준

다음 behavior-level 테스트가 있거나 기존 테스트가 같은 의미로 갱신되어야 한다.

```text
1. helper 설치 후 bin/zebra-gbrain-onboarding은 존재한다.
2. helper 설치 후 bin/launchctl은 존재한다.
3. helper 설치 후 bin/gbrain은 존재하지 않는다.
4. run-gbrain -- --version이 active source repo의 node_modules/.bin/gbrain에 전달된다.
5. node_modules/.bin/gbrain이 없으면 run-gbrain -- --version이 active source repo의 bin/gbrain에 전달된다.
6. 두 built binary가 없고 src/cli.ts가 있으면 run-gbrain -- --version이 bun src/cli.ts로 전달된다.
7. active source repo에 실행 후보가 없으면 PATH에 gbrain이 있어도 run-gbrain은 실패한다.
8. 승인 전 run-gbrain -- autopilot --install ...은 exit 78이고 stderr에 recurring_jobs_decision=autopilot_install이 포함된다.
9. 승인 후 run-gbrain -- autopilot --install ...은 성공하고 autopilot 인자를 active source CLI에 전달한다.
10. Step 1 completed report는 user-visible gbrain이 없으면 gbrain_version_failed로 실패한다.
11. Step 1 completed report는 global/linked user-visible gbrain --version이 성공하면 통과한다.
12. Step 7 nextPrompt에는 zebra-gbrain-onboarding run-gbrain -- autopilot --install이 포함된다.
13. launchctl wrapper 차단/허용 테스트는 계속 통과한다.
```

### 검증 명령 완료 기준

코드 변경 후 에이전트는 최소한 다음을 실행한다.

```bash
swift test --package-path Packages/ZebraVault --filter ZebraGBrainOnboardingStoreTests
```

그리고 Zebra repo 규칙에 따라 tagged Debug reload를 실행한다.

```bash
./scripts/reload.sh --tag gbrain-run-gbrain
```

`reload.sh`는 sandbox 밖 파일을 쓰므로, Codex는 첫 시도부터 escalated permission을 요청해서 실행한다. 성공 후 최종 응답에는 `App path:` 값으로 만든 clickable app link를 포함한다.

### 완료 보고 기준

최종 보고에는 다음을 포함한다.

```text
1. 변경한 파일 목록
2. 제거된 gbrain wrapper와 새 run-gbrain command 요약
3. Step 1 / Step 7 prompt 변경 요약
4. 실행한 테스트와 결과
5. reload.sh 성공 여부와 clickable app link
6. 의도적으로 건드리지 않은 범위: launchctl wrapper, cmux upstream 파일, unrelated untracked docs
```

## 문서화 원칙

이 결정은 Zebra onboarding agent와 향후 디버깅 담당자가 같은 기준을 공유해야 하므로 문서화가 적절하다.

최종 원칙:

```text
Zebra는 `gbrain`을 흉내내지 않는다.
`gbrain`은 실제 설치 CLI만 의미한다.
Zebra 대리 실행은 `zebra-gbrain-onboarding run-gbrain -- ...`가 담당한다.
```

## 범위

이 작업은 ZebraVault 쪽에서 처리 가능하다.

수정 예상 범위:

```text
Packages/ZebraVault/Sources/ZebraVault/AgentOnboarding/ZebraGBrainOnboarding.swift
Packages/ZebraVault/Tests/ZebraVaultTests/ZebraGBrainOnboardingStoreTests.swift
docs/zebra-gbrain-onboarding-wrapper-rename-plan.md
```

cmux upstream 파일은 건드릴 필요가 없다.

기존 untracked 파일 `docs/claude-onboarding-single-terminal-plan-2026-06-12.md`는 이 작업과 무관하므로 제외한다.
