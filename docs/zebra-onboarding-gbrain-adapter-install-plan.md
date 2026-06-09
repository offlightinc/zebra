# Zebra 온보딩 GBrain Adapter Install 계획

[Source: User request from `/Users/han/brain-offlight/tasks/zebra-onboarding-gbrain-adapter-install.md` terminal context, 2026-06-02]

## 요약

Zebra 온보딩의 adapter 단계는 `gbrain-adapter`를 clone 또는 update하고, GBrain 단계에서 resolved된 target에 install한 뒤, adapter overlay가 실제로 사용할 수 있는 상태인지 검증해야 한다. 검증이 끝난 뒤에만 checklist row가 checked가 된다.

명칭 주의: task 제목의 `3. Zebra 온보딩 gbrain-adapter 클론 및 install`은 작업 번호다. 현재 코드 기준 checklist 번호는 `agent=1`, `gbrainRuntime=2`, `gbrain=3`, `adapter=4`다. 이 문서의 오래된 "Step 3" 표현은 adapter 작업을 가리키는 문맥으로 읽되, 구현 시 UI 번호는 `.adapter`의 현재 `number: 4`를 따른다.

이 흐름은 기존 온보딩 Step 1과 Step 2의 구조를 재사용한다.

- Step 1은 이미 primary terminal agent를 정하고 Zebra terminal에서 setup 작업을 시작하는 흐름을 만든다. [Source: `/Users/han/brain-offlight/tasks/zebra-onboarding-agent-cli-scan.md`, 2026-06-02]
- Step 2는 GBrain setup 진행 상황과 완료 receipt를 resolved brain target 기준으로 Zebra-owned state에 기록한다. [Source: `docs/zebra-gbrain-onboarding-recorded-skill-runner-plan.md`, 2026-06-02]
- Step 3은 brain target을 다시 찾거나 고르지 않는다. Step 2의 resolved target receipt에 의존해서, 그 target에 `gbrain-adapter`를 install하고 verify한다. [Source: `Packages/ZebraVault/Sources/ZebraVault/AgentOnboarding/ZebraOnboardingChecklist.swift`, 2026-06-02]

현재 task의 `status`는 `todo`이므로, 이 문서는 완료 기록이 아니라 구현 계획이다. [Source: `/Users/han/brain-offlight/tasks/zebra-onboarding-gbrain-adapter-install.md`, 2026-06-02]

## 출처 맥락

현재 로컬 adapter clone은 다음 위치와 상태다.

```text
/Users/han/gbrain-adapter
origin: https://github.com/namho-hong/gbrain-adapter.git
HEAD: 817578e14f2328dc2828fe0b7a65930d507c080f
latest commit summary: feat: make adapter installable
```

[Source: `/Users/han/gbrain-adapter` git status/log/remote inspection, 2026-06-02]

adapter install command:

```bash
scripts/install.sh --brain <path> [--dry-run]
```

installer는 idempotent하다. 빠진 `goals/README.md`와 `tasks/README.md`를 설치하고, `RESOLVER.md`, `schema.md`, `AGENTS.md`의 adapter-owned fenced block만 replace하며, `.gbrain-adapter/skills/` 아래 adapter skill을 refresh한다. [Source: `/Users/han/gbrain-adapter/README.md`, `/Users/han/gbrain-adapter/scripts/install.sh`, `/Users/han/gbrain-adapter/docs/install-plan.md`, 2026-06-02]

2026-06-09 재확인 기준으로, source repo와 현재 설치된 `brain-offlight` adapter overlay 사이에 drift가 있다.

- `/Users/han/brain-offlight/.gbrain-adapter/skills/team-daily-task-prep/SKILL.md`는 target brain에는 있지만 `/Users/han/gbrain-adapter` source repo에는 없다.
- `brain-offlight`의 `daily-task-manager` skill에는 Zebra ChatPill `worktree:` 힌트 규칙이 추가되어 있지만 source repo의 같은 skill에는 없다.
- `brain-offlight/goals/README.md`와 `brain-offlight/tasks/README.md`는 adapter template보다 더 구체적인 Zebra/worktree 규칙을 포함한다.

따라서 V1 구현 전에 product adapter source를 먼저 정리해야 한다. 현재 source repo의 installer를 그대로 사용하면 새 사용자 target에는 `team-daily-task-prep`와 `worktree:` 규칙이 빠지고, 이미 확장된 target에서는 `daily-task-manager`가 source repo 버전으로 되돌아갈 수 있다. [Source: `/Users/han/gbrain-adapter`, `/Users/han/brain-offlight/.gbrain-adapter`, `/Users/han/brain-offlight/tasks/README.md`, `/Users/han/brain-offlight/goals/README.md`, 2026-06-09]

첫 adapter module은 Goal/Task workflow다.

- `goals/*.md`: time-bound outcome.
- `tasks/*.md`: action task.
- `ops/tasks.md`: bridge mode 중 legacy fallback.
- adapter-aware `router`, `daily-task-manager`, `daily-task-prep` skills.

[Source: `/Users/han/gbrain-adapter/docs/architecture.md`, `/Users/han/gbrain-adapter/docs/task-list.md`, 2026-06-02]

Offlight thin-client wrapper로 GBrain live `search` / `query` / `get`를 시도했지만, network escalation 이후에도 remote OAuth discovery에서 실패했다. 따라서 이 계획은 local task files, Zebra docs, source code, local adapter clone을 fallback context로 사용했다. [Source: local `~/.gbrain-profiles/offlight/gbrain-offlight` command attempts, 2026-06-02]

관련 brain page:

- `/Users/han/brain-offlight/tasks/zebra-onboarding-gbrain-adapter-install.md`
- `/Users/han/brain-offlight/tasks/zebra-onboarding-gbrain-vault-setup.md`
- `/Users/han/brain-offlight/tasks/zebra-onboarding-agent-cli-scan.md`
- `/Users/han/brain-offlight/tasks/zebra-onboarding-checklist-ui-ux.md`

## 제품 흐름

checklist row는 단순하게 유지한다.

```text
adapter verified -> checked
otherwise -> Start
```

Start는 selected primary agent에게 긴 setup packet을 주입하지 않는다. 대신 Zebra-owned helper가 deterministic installer처럼 실행된다. Start는 manual checkmark가 아니며, 자체적으로 완료 처리하지 않는다.

사용자가 보는 흐름:

```text
Step 1: primary agent 선택
  -> Step 2: GBrain install/check 및 target brain repo resolve
  -> Step 4: GBrain source repo sibling에 gbrain-adapter clone/update
  -> Step 4: resolved target에 adapter install dry-run
  -> Step 4: adapter overlay install
  -> Step 4: adapter receipt verify
  -> checklist refresh가 Step 4를 checked 처리
```

Step 3이 incomplete이면 Step 4는 사용자에게 brain target이나 adapter clone 위치를 다시 고르게 하지 않는다. Step 3이 GBrain source repo와 target brain repo resolution의 owner이므로, Step 4는 Step 3 state/receipt가 incomplete인 이유를 보여주고 Step 3 흐름으로 돌려야 한다.

## 핵심 결정

### Product Adapter Source 정리 선행

Step 4 온보딩은 `/Users/han/gbrain-adapter`의 현재 `main`을 그대로 product truth로 삼기 전에, `brain-offlight`에 이미 설치된 overlay 확장분을 source repo로 승격할지 결정해야 한다.

권장 V1 기본값:

```text
source repo = gbrain-adapter product truth
brain-offlight local overlay = source repo로 승격하거나 명시적 local customization으로 분리
```

최소 구현 전 prerequisite:

```text
1. team-daily-task-prep를 product adapter에 포함할지 결정
2. tasks/goals worktree hint를 product adapter에 포함할지 결정
3. daily-task-manager의 worktree 규칙을 source repo에 반영하거나 target-local customization으로 보호
4. installer가 source에 없는 extra installed skills를 삭제하지 않는 현재 정책은 유지
```

이 prerequisite을 정리하지 않으면 Zebra 온보딩이 "clone and install"에는 성공하더라도, 현재 Zebra가 실제로 기대하는 brain workflow와 새 사용자 설치 결과가 달라질 수 있다.

### GBrain Source Repo Sibling Adapter Clone 사용

production path로 `/Users/han/gbrain-adapter`에 의존하지 않는다. 이 경로는 현재 development reference로만 취급한다.

제품 온보딩에서는 adapter 위치를 별도로 묻지 않는다. Step 3 GBrain setup이 기록한 `activeGBrainBinding.sourceRepoPath`의 sibling path를 사용한다.

```text
GBrain source repo: <parent>/gbrain
Adapter source repo: <parent>/gbrain-adapter
```

예시:

```text
/Users/han/gbrain -> /Users/han/gbrain-adapter
/Users/han/dev/gbrain -> /Users/han/dev/gbrain-adapter
```

기본 remote:

```text
https://github.com/namho-hong/gbrain-adapter.git
```

개발 및 향후 repo 이동을 위해 remote/ref만 configurable하게 둔다. 제품 UX에서 local path override를 묻지 않는다.

```text
ZEBRA_GBRAIN_ADAPTER_REMOTE=https://github.com/namho-hong/gbrain-adapter.git
ZEBRA_GBRAIN_ADAPTER_REF=main
```

clone path 처리:

```text
missing or empty
  -> clone

valid gbrain-adapter repo
  -> fetch/checkout selected ref and record commit

non-empty invalid path
  -> do not delete or overwrite; fail with adapter_repo_path_blocked
```

verifier는 단순히 "latest"가 아니라 실제 사용한 adapter path/ref/commit을 기록해야 한다.

### Step 3 Target에 설치

Step 4는 `gbrain-setup-state.json`을 읽고 Step 3이 verify한 동일 target을 resolve한다.

```text
selected vault present
  -> matching receipt.targets entry 사용

selected vault absent
  -> receipt.primaryTargetKey 사용
```

complete한 Step 3 target receipt가 없으면 Step 4는 다음 reason으로 실패한다.

```text
missing_gbrain_setup_receipt
missing_active_gbrain_source_binding
receipt_target_missing
target_not_verified
```

이렇게 해야 agent가 home 또는 편한 cwd에서 시작했다는 이유로 adapter를 잘못된 repo에 install하는 실패를 막을 수 있다.

### Adapter State 분리

Step 4 전용 state file을 추가한다.

```text
~/Library/Application Support/zebra/onboarding/gbrain-adapter-state.json
```

Step 3은 GBrain source repo와 target readiness의 owner다. Step 4는 adapter clone/install readiness의 owner다. state를 분리하면 GBrain receipt가 adapter-specific install log로 비대해지는 것을 피할 수 있다.

제안 schema:

```text
schemaVersion
currentRunId
adapterSourceBinding
  repoPath
  remote
  ref
  commit
  status
progress
  phase
  targetKey
  targetVaultPath
  adapterRepoPath
  adapterRemote
  adapterRef
  adapterCommit
  dryRunCompletedAt
  installStartedAt
  installCompletedAt
  lastFailure
receipt
  targetKey
  targetVaultPath
  adapterRepoPath
  adapterRemote
  adapterCommit
  installerPath
  installedAt
  verifiedAt
  complete
  checks
    targetIsBrainDataRepo
    adapterSkillsPresent
    resolverBlockPresent
    schemaBlockPresent
    agentsBlockPresent
    goalsReadmePresent
    tasksReadmePresent
    dryRunIdempotent
  reasons
```

## Helper 계약

Step 4용 Zebra-owned helper command를 추가한다.

```text
zebra-gbrain-adapter-onboarding
```

`ZebraGBrainRuntimeOnboardingStore`가 현재 `zebra-gbrain-runtime-onboarding`을 쓰는 방식처럼 onboarding support `bin/` directory에 생성할 수 있다. 이렇게 하면 구현을 `Packages/ZebraVault/**` 안에 둘 수 있고, standalone script를 bundle해야 할 강한 이유가 생기기 전까지 새 `Resources/` touchpoint를 추가하지 않아도 된다. [Source: `Packages/ZebraVault/Sources/ZebraVault/AgentOnboarding/ZebraGBrainRuntimeOnboarding.swift`, 2026-06-09]

외부 subcommands:

```text
run
  전체 deterministic flow를 실행한다. GBrain source sibling adapter path 계산, clone/update, target resolve, dry-run, install, verify를 순서대로 수행한다.

status
  UI/debug용 progress와 receipt JSON을 출력한다.
```

Dry-run, install, verify는 별도 UI 호출 subcommand가 아니라 `run` 내부 phase다. Swift Start action은 `run`만 호출한다. UI가 `dry-run -> install -> verify`를 직접 chain하지 않는다. terminal agent는 이 단계에서 판단하지 않고, helper 출력과 exit status만 보여주는 실행 표면이다.

## 재개 모델

모든 phase는 idempotent해야 한다.

- `run`: 현재 state를 보고 필요한 phase부터 이어서 실행한다.
- `clone/update`: sibling repo가 이미 있으면 fetch하고 target ref를 checkout한다. 이미 recorded commit이면 reuse한다.
- `dry-run`: 반복 실행 가능하며 recorded dry-run output을 갱신한다.
- `install`: adapter installer가 fenced block만 replace하고 skills를 refresh하므로 반복 실행 가능하다.
- `verify`: 반복 실행 가능하며 receipt를 갱신한다.

resume rules:

```text
state missing
  -> clone/update부터 시작

adapter repo prepared, dry-run missing
  -> dry-run부터 resume

dry-run complete, install missing
  -> install부터 resume

install complete, receipt incomplete
  -> verify부터 resume

receipt complete but target or adapter commit changed
  -> row check 전에 다시 verify
```

target brain repo에 install 전 dirty working tree가 있으면, helper는 destructive action을 하지 않고 중단한다. 특히 installer가 만질 수 있는 `RESOLVER.md`, `schema.md`, `AGENTS.md`, `goals/README.md`, `tasks/README.md`, `.gbrain-adapter/`가 dirty면 `target_dirty` reason을 기록하고 사용자가 정리한 뒤 재시작하게 한다.

## 검증 기준

Step 4는 모든 required check가 통과할 때만 complete다.

필수 installed-file checks:

```text
target is a brain data repo, not a gbrain engine repo
.gbrain-adapter/skills/router/SKILL.md exists
.gbrain-adapter/skills/daily-task-manager/SKILL.md exists
.gbrain-adapter/skills/daily-task-prep/SKILL.md exists
RESOLVER.md contains gbrain-adapter goals-tasks fence
schema.md contains gbrain-adapter goals-tasks fence
AGENTS.md contains gbrain-adapter goals-tasks fence
goals/README.md exists
tasks/README.md exists
```

필수 install checks:

```text
adapter repo path exists
adapter commit is recorded
scripts/install.sh exists and is runnable with bash
dry-run has completed for the same targetKey + adapterCommit
install completed after that dry-run
```

GBrain runtime `search/get/query` probe는 Zebra Step 4 V1 자동 checklist gate의 완료 조건이 아니다. `gbrain-adapter` rollout 문서에는 `gbrain get`, `gbrain search`, task lookup behavior 같은 수동 운영 검증 항목이 있지만, 현재 `scripts/install.sh` 자체는 GBrain runtime을 호출하지 않고 target repo 파일만 설치한다. Step 3이 이미 GBrain readiness와 source registration을 소유하므로, Step 4 자동 완료는 installed adapter files verification으로 처리한다.

## Helper UX

Step 4 startup line은 setup packet을 만들지 않는다. `ZebraGBrainAdapterOnboardingStore.prepareLaunch()`가 helper를 설치하고 다음 형태의 line을 반환한다.

```text
cd <onboarding-workdir>
export ZEBRA_GBRAIN_ADAPTER_STATE=<.../gbrain-adapter-state.json>
export ZEBRA_GBRAIN_SETUP_STATE=<.../gbrain-setup-state.json>
export ZEBRA_GBRAIN_ADAPTER_REMOTE=<remote>
export ZEBRA_GBRAIN_ADAPTER_REF=<ref>
export PATH=<onboarding-bin>:$PATH
zebra-gbrain-adapter-onboarding run
```

helper output은 사용자가 확인할 수 있게 단계별로 짧게 보여준다.

```text
GBrain source repo: ...
Adapter repo: ...
Target brain repo: ...
Dry-run: ok
Install: ok
Verify: ok
```

## UI 동작

Checklist 감지 규칙:

```text
adapter row checked =
  Step 3 resolved target verifies
  AND adapter receipt exists for the same targetKey
  AND adapter receipt complete == true
  AND adapter commit/repo still exists
  AND required installed adapter files still exist

adapter row Start =
  checked condition is false
```

selected vault 변경:

```text
selected vault changes
  -> Step 3 target resolution refresh
  -> Step 4는 new targetKey와 matching되는 adapter receipt를 찾음
  -> 없으면 Start 표시
```

adapter receipt는 target-specific이어야 한다. 한 brain에 adapter를 install했다고 다른 selected vault의 Step 4가 checked되면 안 된다.

## 구현 단계

1. 계획 및 state contract
   - 이 문서를 추가한다.
   - `gbrain-adapter`의 product remote/ref를 확정한다.
   - runtime-probe policy를 strict/pragmatic 중 결정한다.

2. Helper 및 store
   - `Packages/ZebraVault/Sources/ZebraVault/AgentOnboarding/` 아래 `ZebraGBrainAdapterOnboardingStore`를 추가한다.
   - `zebra-gbrain-adapter-onboarding`을 Application Support `bin/`에 생성한다.
   - `run`, `dry-run`, `install`, `verify`, `status`를 구현한다.

3. Checklist 통합
   - `ZebraOnboardingChecklistCommand`의 현재 generic adapter prompt를 helper `run` startup line으로 교체한다.
   - `ZebraOnboardingChecklistStore.refreshDetectedCompletion()`에 adapter receipt detection을 추가한다.
   - 기존 onboarding state files와 함께 `gbrain-adapter-state.json`을 watch한다.

4. Agent UX
   - terminal flow는 Step 2 runtime helper처럼 deterministic command output 중심으로 유지한다.
   - 시작 시 concise resume status를 보여준다.
   - install 전에 dry-run summary를 보여준다.
   - target git status가 dirty이면 중단하고 정리 후 재시작하도록 안내한다.

5. 검증 coverage
   - receipt parsing과 selected-vault target matching unit coverage를 추가한다.
   - temporary target brain과 local fake adapter repo를 사용하는 helper resume phase shell-level tests를 추가한다.
   - 두 번째 install이 idempotent하고 fence를 duplicate하지 않는 repeat-install test를 추가한다.

6. Build
   - code 변경 후 Zebra local dev rule에 따라 escalation으로 `./scripts/reload.sh --tag <adapter-install-tag>`를 실행한다.

## 테스트 케이스

- Step 3 미완료
  - Step 4는 어디에도 install하지 않는다.
  - helper는 missing GBrain source/target reason을 기록한다.

- 새 target, clean git status
  - adapter clone.
  - dry-run.
  - install.
  - receipt verify.
  - checklist row checked.

- clone 이후 interrupted
  - rerun은 dry-run부터 resume.

- dry-run 이후 interrupted
  - rerun은 install부터 resume.

- install 이후 interrupted
  - rerun은 verify부터 resume.

- 반복 install
  - fenced block은 duplicated가 아니라 replaced된다.
  - 기존 non-adapter content는 보존된다.

- Dirty target repo
  - helper가 dirty status를 기록하고 install 전에 중단한다.
  - destructive git operation은 자동 실행하지 않는다.

- selected vault 변경
  - 이전 target receipt가 새 target을 checked 처리하지 않는다.

- adapter repo ref 변경
  - 새 commit이 install될 때까지 기존 receipt를 reverify하거나 stale로 표시한다.

## 열린 질문

- Product remote: V1에서 `https://github.com/namho-hong/gbrain-adapter.git`를 사용할지, shipping 전에 adapter repo를 `offlightinc` 아래로 옮길지?
- Product source contents: `team-daily-task-prep`, Zebra ChatPill `worktree:` 힌트, `brain-offlight`의 richer `tasks/README.md`/`goals/README.md`를 adapter source로 승격할지, 아니면 target-local customization으로 유지할지?
- Commit 동작: Zebra가 target brain diff review/commit을 사용자에게 안내만 할지, verification 이후 명시적인 "commit adapter install" step을 제공할지?

## 권장 방향

pragmatic V1을 사용한다.

0. 먼저 product adapter source drift를 정리한다. 새 사용자에게 설치될 source repo가 현재 Zebra가 기대하는 adapter overlay와 맞아야 한다.
1. target은 Step 3 receipt에서만 resolve한다.
2. adapter는 Step 3의 active GBrain source repo sibling path에 clone/update한다.
3. `scripts/install.sh --brain <target> --dry-run`을 실행한다.
4. target git status가 dirty이면 install 전에 중단한다.
5. install을 실행한다.
6. installed adapter files를 verify하고 target-specific receipt를 기록한다.
7. GBrain runtime probes는 V1 완료 조건에서 제외한다.

이 방향은 기존 onboarding model과 유사하고, 모든 phase를 resumable하게 만들며, 잘못된 brain repo를 조용히 바꾸지 않는 terminal-guided path를 사용자에게 제공한다.

## 확인용 요약

구현 전 확인할 결정은 다음이다.

```text
1. adapter clone 위치는 묻지 않는다.
2. adapter clone 위치는 GBrain source repo sibling으로 자동 결정한다.
   <parent>/gbrain -> <parent>/gbrain-adapter
3. setup packet은 쓰지 않는다.
4. helper는 `zebra-gbrain-adapter-onboarding run` 단일 진입점으로 실행한다.
5. install target은 Step 3 GBrain receipt의 resolved target만 쓴다.
6. dirty target은 자동 install하지 않고 중단한다.
7. 완료는 installed adapter files verify + adapter receipt로 처리한다.
8. GBrain runtime search/get/query probe는 Zebra Step 4 V1 자동 checklist gate의 완료 조건이 아니다.
```
