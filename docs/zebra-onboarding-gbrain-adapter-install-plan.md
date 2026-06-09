# Zebra 온보딩 GBrain Adapter Install 계획

[Source: User request from `/Users/han/brain-offlight/tasks/zebra-onboarding-gbrain-adapter-install.md` terminal context, 2026-06-02]

## 요약

Zebra 온보딩 Step 3은 `gbrain-adapter`를 clone 또는 update하고, Step 2에서 resolved된 GBrain target에 install한 뒤, adapter overlay가 실제로 사용할 수 있는 상태인지 검증해야 한다. 검증이 끝난 뒤에만 checklist row가 checked가 된다.

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

Start는 selected primary agent를 Zebra terminal에서 열고 adapter-specific setup packet을 주입한다. Start는 manual checkmark가 아니며, 자체적으로 완료 처리하지 않는다.

사용자가 보는 흐름:

```text
Step 1: primary agent 선택
  -> Step 2: GBrain install/check 및 target brain repo resolve
  -> Step 3: gbrain-adapter clone/update
  -> Step 3: resolved target에 adapter install dry-run
  -> Step 3: adapter overlay install
  -> Step 3: adapter receipt verify
  -> checklist refresh가 Step 3을 checked 처리
```

Step 2가 incomplete이면 Step 3은 사용자에게 brain target을 다시 고르게 하지 않는다. Step 2가 target resolution과 GBrain source/profile readiness의 owner이므로, Step 3은 사용자를 Step 2 흐름으로 돌려야 한다.

## 핵심 결정

### Zebra 관리 Adapter Clone 사용

production path로 `/Users/han/gbrain-adapter`에 의존하지 않는다. 이 경로는 현재 development reference로만 취급한다.

제품 온보딩에서는 Zebra-managed Application Support 아래에 clone한다.

```text
~/Library/Application Support/zebra/onboarding/gbrain-adapter/repo
```

기본 remote:

```text
https://github.com/namho-hong/gbrain-adapter.git
```

개발 및 향후 repo 이동을 위해 configurable하게 둔다.

```text
ZEBRA_GBRAIN_ADAPTER_REPO=/Users/han/gbrain-adapter
ZEBRA_GBRAIN_ADAPTER_REMOTE=https://github.com/namho-hong/gbrain-adapter.git
ZEBRA_GBRAIN_ADAPTER_REF=main
```

verifier는 단순히 "latest"가 아니라 실제 사용한 adapter commit을 기록해야 한다.

### Step 2 Target에 설치

Step 3은 `gbrain-setup-state.json`을 읽고 Step 2가 verify한 동일 target을 resolve한다.

```text
selected vault present
  -> matching receipt.targets entry 사용

selected vault absent
  -> receipt.primaryTargetKey 사용
```

complete한 Step 2 target receipt가 없으면 Step 3은 다음 reason으로 실패한다.

```text
missing_gbrain_setup_receipt
receipt_target_missing
target_not_verified
```

이렇게 해야 agent가 home 또는 편한 cwd에서 시작했다는 이유로 adapter를 잘못된 repo에 install하는 실패를 막을 수 있다.

### Adapter State 분리

Step 3 전용 state file을 추가한다.

```text
~/Library/Application Support/zebra/onboarding/gbrain-adapter-state.json
```

Step 2는 GBrain readiness의 owner다. Step 3은 adapter clone/install readiness의 owner다. state를 분리하면 GBrain receipt가 adapter-specific install log로 비대해지는 것을 피할 수 있다.

제안 schema:

```text
schemaVersion
currentRunId
selectedAgent
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
  waitingForUser
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
    gbrainSearchOrGetOk
  reasons
```

## Helper 계약

Step 3용 Zebra-owned helper command를 추가한다.

```text
zebra-gbrain-adapter-onboarding
```

`ZebraGBrainOnboardingStore`가 현재 `zebra-gbrain-onboarding`을 쓰는 방식처럼 onboarding support `bin/` directory에 생성할 수 있다. 이렇게 하면 구현을 `Packages/ZebraVault/**` 안에 둘 수 있고, standalone script를 bundle해야 할 강한 이유가 생기기 전까지 새 `Resources/` touchpoint를 추가하지 않아도 된다. [Source: `Packages/ZebraVault/Sources/ZebraVault/AgentOnboarding/ZebraGBrainOnboarding.swift`, 2026-06-02]

제안 subcommands:

```text
prompt
  selected terminal agent에 주입할 startup packet을 만든다.

prepare
  Step 2 target을 resolve하고, gbrain-adapter를 clone/fetch한 뒤 adapter commit을 기록한다.

dry-run
  scripts/install.sh --brain <target> --dry-run을 실행하고 output을 기록한다.

install
  기록된 dry-run 이후 scripts/install.sh --brain <target>을 실행한다.

verify
  target artifacts와 optional GBrain search/get behavior를 검증한다.

status
  UI/debug용 progress와 receipt JSON을 출력한다.

report
  agent가 JSON을 직접 수정하지 않고 waiting/failure/resume note를 기록하게 한다.
```

Swift Start action은 `prompt`만 호출한다. prompt가 agent에게 사용 가능한 helper command를 알려준다. UI가 `prepare -> dry-run -> install -> verify`를 직접 chain하지 않는다. terminal agent는 git status, credential, user confirmation에서 멈춰야 할 수 있기 때문이다.

## 재개 모델

모든 phase는 idempotent해야 한다.

- `prepare`: repo가 이미 있으면 fetch하고 target ref를 checkout한다. 이미 recorded commit이면 reuse한다.
- `dry-run`: 반복 실행 가능하며 recorded dry-run output을 갱신한다.
- `install`: adapter installer가 fenced block만 replace하고 skills를 refresh하므로 반복 실행 가능하다.
- `verify`: 반복 실행 가능하며 receipt를 갱신한다.

resume rules:

```text
state missing
  -> prepare부터 시작

adapter repo prepared, dry-run missing
  -> dry-run부터 resume

dry-run complete, install missing
  -> install부터 resume

install complete, receipt incomplete
  -> verify부터 resume

receipt complete but target or adapter commit changed
  -> row check 전에 다시 verify
```

target brain repo에 install 전 dirty working tree가 있으면, agent는 관련 status를 보여주고 진행 여부를 물어야 한다. dirty state가 installer가 touch할 파일을 포함하면 더 명시적으로 물어야 한다. user work를 silent stash, reset, overwrite하지 않는다.

## 검증 기준

Step 3은 모든 required check가 통과할 때만 complete다.

필수 artifact checks:

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

GBrain 사용 가능 시 runtime checks:

```text
gbrain get tasks/README or equivalent known page succeeds
gbrain search/query can find a known adapter-installed phrase
active adapter instructions are discoverable from the target repo
```

remote GBrain이 unavailable이어도 artifact verification은 install receipt를 pass할 수 있다. 다만 receipt에는 `gbrain_runtime_probe_unavailable` 같은 reason을 남겨야 한다. checklist policy는 여기서 product decision이 필요하다.

- strict 방식: runtime probe가 pass할 때까지 Step 3을 check하지 않는다.
- pragmatic V1 방식: artifact install이 complete이고 Step 2 GBrain receipt가 아직 valid하면 Step 3을 check하되, runtime probe warning을 유지한다.

권장 V1 선택지는 pragmatic이다. Step 2가 이미 GBrain runtime readiness를 소유한다. Step 3은 adapter install state를 증명하고, runtime probe failure는 전체 row를 block하기보다 warning으로 surface한다.

## Agent Prompt 형태

Step 3 startup prompt에는 다음을 포함한다.

```text
You are Zebra's gbrain-adapter install agent.

Use the Step 2 GBrain setup receipt as the only source of target truth.
Do not choose a new brain repo target unless Step 2 is incomplete, and in that case route the user back to Step 2.

Clone or update gbrain-adapter from the provided remote/ref.
Record the exact commit.
Run dry-run before install.
Do not modify upstream gbrain.
Do not rewrite target brain content outside adapter-owned fences.
Do not delete or migrate ops/tasks.md.
If target git status is dirty, show the status and ask before installing.

Before claiming completion, run:
zebra-gbrain-adapter-onboarding verify
```

prompt에는 path도 포함한다.

```text
GBRAIN_SETUP_STATE
ADAPTER_STATE
TARGET_VAULT_PATH
TARGET_KEY
ADAPTER_REPO_PATH
ADAPTER_REMOTE
ADAPTER_REF
HELPER_COMMANDS
```

## UI 동작

Checklist 감지 규칙:

```text
adapter row checked =
  Step 2 resolved target verifies
  AND adapter receipt exists for the same targetKey
  AND adapter receipt complete == true
  AND adapter commit/repo still exists
  AND required target artifacts still exist

adapter row Start =
  checked condition is false
```

selected vault 변경:

```text
selected vault changes
  -> Step 2 target resolution refresh
  -> Step 3는 new targetKey와 matching되는 adapter receipt를 찾음
  -> 없으면 Start 표시
```

adapter receipt는 target-specific이어야 한다. 한 brain에 adapter를 install했다고 다른 selected vault의 Step 3이 checked되면 안 된다.

## 구현 단계

1. 계획 및 state contract
   - 이 문서를 추가한다.
   - `gbrain-adapter`의 product remote/ref를 확정한다.
   - runtime-probe policy를 strict/pragmatic 중 결정한다.

2. Helper 및 store
   - `Packages/ZebraVault/Sources/ZebraVault/AgentOnboarding/` 아래 `ZebraGBrainAdapterOnboardingStore`를 추가한다.
   - `zebra-gbrain-adapter-onboarding`을 Application Support `bin/`에 생성한다.
   - `prompt`, `prepare`, `dry-run`, `install`, `verify`, `status`, `report`를 구현한다.

3. Checklist 통합
   - `ZebraOnboardingChecklistCommand`의 현재 generic Step 3 prompt를 새 adapter prompt로 교체한다.
   - `ZebraOnboardingChecklistStore.refreshDetectedCompletion()`에 adapter receipt detection을 추가한다.
   - 기존 onboarding state files와 함께 `gbrain-adapter-state.json`을 watch한다.

4. Agent UX
   - terminal flow는 Step 1, Step 2와 유사하게 유지한다.
   - 시작 시 concise resume status를 보여준다.
   - install 전에 dry-run summary를 보여준다.
   - target git status가 dirty이면 진행 전에 묻는다.

5. 검증 coverage
   - receipt parsing과 selected-vault target matching unit coverage를 추가한다.
   - temporary target brain과 local fake adapter repo를 사용하는 helper resume phase shell-level tests를 추가한다.
   - 두 번째 install이 idempotent하고 fence를 duplicate하지 않는 repeat-install test를 추가한다.

6. Build
   - code 변경 후 Zebra local dev rule에 따라 escalation으로 `./scripts/reload.sh --tag <adapter-install-tag>`를 실행한다.

## 테스트 케이스

- Step 2 미완료
  - Step 3은 어디에도 install하지 않는다.
  - prompt는 GBrain setup target resolution으로 되돌린다.

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
  - agent가 dirty status를 report하고 install 전에 묻는다.
  - destructive git operation은 자동 실행하지 않는다.

- selected vault 변경
  - 이전 target receipt가 새 target을 checked 처리하지 않는다.

- adapter repo ref 변경
  - 새 commit이 install될 때까지 기존 receipt를 reverify하거나 stale로 표시한다.

## 열린 질문

- Product remote: V1에서 `https://github.com/namho-hong/gbrain-adapter.git`를 사용할지, shipping 전에 adapter repo를 `offlightinc` 아래로 옮길지?
- Runtime probe 엄격도: Step 3이 `gbrain search/query/get`를 반드시 요구해야 하는지, 아니면 V1에서는 artifact install + Step 2 runtime readiness로 충분한지?
- Commit 동작: Zebra가 target brain diff review/commit을 사용자에게 안내만 할지, verification 이후 명시적인 "commit adapter install" step을 제공할지?

## 권장 방향

pragmatic V1을 사용한다.

1. target은 Step 2 receipt에서만 resolve한다.
2. adapter를 Zebra Application Support에 clone/update한다.
3. `scripts/install.sh --brain <target> --dry-run`을 실행한다.
4. target git status가 dirty이면 install 전에 묻는다.
5. install을 실행한다.
6. adapter artifacts를 verify하고 target-specific receipt를 기록한다.
7. Step 2 runtime readiness가 invalid해진 경우가 아니면 GBrain runtime probes는 warning으로 처리한다.

이 방향은 기존 onboarding model과 유사하고, 모든 phase를 resumable하게 만들며, 잘못된 brain repo를 조용히 바꾸지 않는 terminal-guided path를 사용자에게 제공한다.
