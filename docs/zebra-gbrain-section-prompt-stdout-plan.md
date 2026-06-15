# GBrain 섹션별 stdout 프롬프트 전달 계획

## 요약

현재 GBrain 3단계 설치는 agent에게 긴 setup packet을 한 번에 읽게 하는 방식이다. 이 방식은 prompt가 길어져서 agent가 중간 내용을 놓치거나, 섹션 순서를 건너뛰거나, 완료 보고 없이 임의로 진행하는 문제가 생길 수 있다.

이번 변경의 방향은 GBrain 설치를 `INSTALL_FOR_AGENTS.md`의 `## Step ...` 섹션 단위로 나누고, agent가 한 섹션을 끝낼 때마다 helper command stdout으로 다음 섹션 prompt를 받게 만드는 것이다.

핵심 흐름은 다음과 같다.

```text
첫 실행
-> 현재 docs snapshot의 INSTALL_FOR_AGENTS.md에서 첫 Step 섹션 prompt 생성
-> agent는 그 섹션만 수행

agent가 섹션 완료 후:
zebra-gbrain-onboarding report --status completed --section "<현재 섹션>"
-> helper가 완료 report를 처리
-> 다음 incomplete 섹션을 계산
-> docsSnapshotPath/INSTALL_FOR_AGENTS.md에서 다음 섹션 본문 추출
-> stdout JSON에 nextPrompt로 반환
-> agent는 같은 TUI 안에서 nextPrompt를 보고 다음 섹션 진행
```

Hermes는 현재 Zebra launcher 기준으로 실행 중인 TUI에 안정적인 외부 prompt 주입 표면이 애매하다. 그래서 Hermes/OpenClaw 공통으로, 외부 TUI 주입 대신 agent가 이미 실행한 helper command의 stdout을 prompt 전달 채널로 쓴다.

`nextPrompt`는 절대 Zebra 코드에 Step 본문을 하드코딩하지 않는다. 항상 현재 run의 `docsSnapshotPath`에 저장된 `INSTALL_FOR_AGENTS.md`에서 해당 `## Step ...` 블록을 추출해서 만든다. 따라서 GBrain의 `INSTALL_FOR_AGENTS.md`가 업데이트되면 다음 `prepareLaunch`가 새 snapshot/manifest를 만들고, 새 run의 `nextPrompt`도 업데이트된 문서 기준으로 바뀐다.

단, 한 번 시작된 run 중간에는 같은 docs snapshot을 계속 사용한다. Step 1은 옛 문서, Step 2는 새 문서처럼 섞이지 않게 하기 위해서다. 문서 업데이트 반영은 다음 launch/run부터 적용한다.

이번 v1은 최소 구조 변경이다. trusted store, Keychain receipt, Zebra UI decision confirmation은 넣지 않는다. agent가 state 파일을 직접 조작하거나 사용자 선택을 임의로 기록하는 문제가 계속 발생하면, 그때 별도 trusted decision/receipt 구조를 설계한다.

## 현재 코드 기준

주요 구현 위치는 `Packages/ZebraVault/Sources/ZebraVault/AgentOnboarding/ZebraGBrainOnboarding.swift`이다.

현재 구조:

- `prepareLaunch`가 docs snapshot과 전체 setup packet을 만든다.
- `bootstrapPrompt`는 agent에게 전체 setup packet을 읽으라고 지시한다.
- runtime launcher는 OpenClaw/Hermes에 bootstrap prompt를 넘긴다.
- embedded Python helper의 `report()`는 `progress.completedSections`를 업데이트하고 짧은 JSON만 stdout으로 출력한다.
- `DocsSection`은 현재 `title`과 `hash`만 갖고 있고 section body는 갖고 있지 않다.

따라서 `nextPrompt` 생성을 위해서는 helper가 `docsSnapshotPath/INSTALL_FOR_AGENTS.md`를 다시 읽고, manifest의 다음 section title에 해당하는 `## Step ...` 블록을 추출해야 한다.

## 수정 방향

- 초기 prompt를 "전체 setup packet 실행" 중심에서 "현재 섹션만 수행" 중심으로 바꾼다.
  - setup packet은 reference/fallback으로 유지한다.
  - agent에게 첫 section prompt를 주고, 완료 후 반드시 `report completed`를 호출하라고 지시한다.
  - agent가 다음 섹션을 스스로 추측하거나 전체 문서를 한 번에 끝내려고 하지 않게 한다.

- helper script에 section prompt 생성 로직을 추가한다.
  - `docsSnapshotPath`에서 `INSTALL_FOR_AGENTS.md`를 읽는다.
  - manifest의 `installForAgentsSections` 순서를 기준으로 다음 incomplete section을 찾는다.
  - 해당 section title의 `## Step ...` 본문만 추출한다.
  - 추출한 본문에 Zebra 공통 지시를 붙여 `nextPrompt`를 만든다.

- `report completed` 성공 stdout을 확장한다.
  - 기존 JSON 응답은 유지한다.
  - 성공 시 다음 필드를 추가한다.
    - `nextSection`
    - `nextPrompt`
    - `nextPromptPath`
  - `nextPrompt`가 primary 전달 경로다.
  - `nextPromptPath`는 긴 prompt 재읽기, 디버깅, 복구용 fallback이다.

- report가 reject되는 경우에는 다음 섹션 prompt를 주지 않는다.
  - guard 실패 시에는 기존처럼 실패 reason을 반환한다.
  - 가능하면 현재 섹션을 계속하기 위한 repair guidance만 포함한다.
  - 실패한 상태에서 다음 Step prompt가 노출되면 안 된다.

- 마지막 INSTALL_FOR_AGENTS 섹션 완료 후에는 다음 Step prompt 대신 verify prompt를 반환한다.
  - 기존 `zebra-gbrain-onboarding verify --target ... --source-id ... --method ...` 흐름을 안내한다.
  - 최종 verify가 통과해야 Zebra checklist가 완료될 수 있다는 기존 정책은 유지한다.

## Step 3 / Zebra hard gate 유지

섹션별 prompt로 바꾸더라도 기존 Step 3 관련 Zebra hard gate는 유지되어야 한다. 특히 `INSTALL_FOR_AGENTS.md`의 Step 3 본문만 던지는 것이 아니라, Zebra가 기존 setup packet에서 강제하던 안전 규칙을 함께 붙여야 한다.

Step 3 prompt에는 다음 방향이 반드시 포함된다.

- topology 선택 전에는 `gbrain init`, `gbrain init --pglite`, Supabase/Postgres setup을 실행하지 않는다.
- local PGLite 또는 Supabase/Postgres 선택은 사용자에게 명시적으로 물어본 뒤 진행한다.
- brain repo target은 topology 선택 이후 별도 단계로 물어본다.
- embedding provider 또는 deferred/no-embedding 선택을 agent가 임의로 하지 않는다.
- `gbrain init --pglite --no-embedding`은 사용자가 명시적으로 선택한 경우에만 허용한다.
- target/source registration/import/verify 순서는 기존 Zebra hard gate를 따른다.
- Step 4 이전에는 resolved target이 GBrain source로 등록되어 있고, `gbrain sources current --json` / `gbrain sources list --json`가 같은 source id와 target path를 가리키는지 확인해야 한다.

즉 `nextPrompt`의 설치 본문은 GBrain 문서에서 동적으로 가져오되, Zebra의 안전 가드는 코드에서 유지해서 section prompt에 덧붙인다.

## 완료 기준

구현 완료는 agent가 실행해서 확인할 수 있어야 한다.

필수 테스트 명령:

```bash
swift test --package-path Packages/ZebraVault --filter ZebraGBrainOnboardingStoreTests
```

필수 테스트 시나리오:

- `report --status completed --section "Step 1: ..."` 성공 시 stdout JSON에 `nextSection == "Step 2: ..."`가 포함된다.
- 같은 stdout JSON에 비어 있지 않은 `nextPrompt`가 포함된다.
- `nextPrompt`는 현재 run의 `docsSnapshotPath/INSTALL_FOR_AGENTS.md`에서 추출한 Step 2 본문을 포함한다.
- Step 2 prompt에는 Step 3 본문이 섞이지 않는다.
- Step 3으로 넘어가는 prompt에는 기존 topology / PGLite / target / embedding hard gate 문구가 포함된다.
- guard 실패 케이스에서는 `nextPrompt`와 `nextPromptPath`가 나오지 않는다.
- 마지막 manifest section 완료 후에는 다음 install section이 아니라 verify 안내 prompt가 나온다.
- `nextPromptPath` 파일이 존재하고, stdout의 `nextPrompt`와 같은 내용을 담는다.
- `INSTALL_FOR_AGENTS.md` 내용을 바꾼 fake docs snapshot을 사용한 테스트에서, `nextPrompt`가 하드코딩 문구가 아니라 snapshot 문서 내용을 반영한다.
- 한 run 안에서는 같은 `docsSnapshotPath` 기준으로 prompt가 생성되어, 중간에 외부 문서가 바뀌어도 run 중 prompt 기준이 섞이지 않는다.

코드 변경 후 Zebra repo 규칙에 따라 Debug reload를 실행한다.

```bash
./scripts/reload.sh --tag gbrain-section-stdout
```

## 합의한 방향 확인용 요약

우리가 합의한 방향은 "지금은 큰 신뢰 저장소나 UI 확인 구조를 만들지 않고, 먼저 stdout 기반 섹션 prompt 전달만 최소 변경으로 넣자"이다.

Agent는 한 섹션을 끝낼 때 `zebra-gbrain-onboarding report --status completed --section ...`를 호출해야 다음 섹션 prompt를 받는다. Hermes에 중간 prompt를 직접 주입하지 않고, helper command stdout을 prompt 전달 채널로 쓴다.

각 `nextPrompt`는 하드코딩된 Step 문구가 아니라, 현재 run의 `docsSnapshotPath/INSTALL_FOR_AGENTS.md`에서 해당 `## Step ...` 본문을 추출해서 만든다. GBrain 문서가 업데이트되면 다음 launch/run부터 새 문서 기준 prompt가 생성된다. 한 run 안에서는 같은 snapshot을 유지해서 Step 기준이 섞이지 않게 한다.

기존 Step 3의 중요한 규칙, 특히 PGLite 선택, Supabase/Postgres 선택, target 결정, embedding/no-embedding 선택 관련 가드는 새 섹션별 prompt에도 반드시 포함한다.

이번 v1에서는 agent가 state 파일을 직접 조작하거나 사용자 선택을 마음대로 기록하는 문제를 완전히 해결하지 않는다. 실제로 그런 문제가 계속 발생하면 다음 단계로 Zebra trusted store, Keychain-backed receipt, Zebra UI decision confirmation을 별도 설계한다.

## Handoff 메모

현재 구현은 위 v1 방향을 따른다. 주요 변경은 `ZebraGBrainOnboardingStore`의 helper/report stdout 경로와 해당 테스트에 있다.

- `report --status completed`가 성공하면 기존 progress JSON에 더해 다음 섹션 안내를 반환한다.
- 반환 필드는 `nextSection`, `nextPrompt`, `nextPromptPath`이다.
- `nextPrompt`는 현재 run의 `docsSnapshotPath/INSTALL_FOR_AGENTS.md`에서 다음 `## Step ...` 섹션 본문을 추출해 만든다.
- `nextPromptPath`는 같은 prompt를 파일로 저장한 fallback/debug 경로다.
- guard 실패나 rejected report에서는 다음 섹션 prompt를 반환하지 않는다.
- 마지막 install section 완료 후에는 다음 Step prompt 대신 verify 안내 prompt를 반환한다.
- Step 3으로 진입하는 prompt에는 topology, PGLite/Supabase 선택, target, embedding 관련 Zebra hard gate가 계속 붙는다.
- Subchecklist/checklist 완료 판단은 기존 state/progress/report 흐름에 연결되어 있으며, stdout prompt는 다음 작업 안내 채널만 추가한다.

검증된 명령:

```bash
swift test --package-path Packages/ZebraVault --filter ZebraGBrainOnboardingStoreTests
./scripts/reload.sh --tag gbrain-section-stdout
```

검증 결과:

- `ZebraGBrainOnboardingStoreTests` 통과.
- `gbrain-section-stdout` Debug reload 빌드 통과.

주의:

- `Sources/TerminalImageTransfer.swift`에 있던 `@_optimize(none)` 임시 우회는 GBrain 작업과 무관한 upstream 파일 변경이라 제거했다.
- `docs/claude-onboarding-single-terminal-plan-2026-06-12.md`는 이 stdout handoff 변경과 별도 문서라 현재 커밋 대상에서 제외했다.
