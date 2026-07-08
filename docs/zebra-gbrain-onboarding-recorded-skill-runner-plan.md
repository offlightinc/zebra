# Zebra GBrain Onboarding Recorded Skill Runner Plan

[Source: Codex/Zebra planning conversation, 2026-06-02]

## 요약

Zebra의 GBrain onboarding은 전통적인 설치 스크립트가 아니라 "기록 가능한 setup skill runner"로 만든다. 실제 설치와 판단은 선택된 terminal agent가 최신 GBrain `INSTALL_FOR_AGENTS.md` snapshot을 읽고 수행한다. Zebra는 문서 snapshot, 진행 기록, 재개 상태, 검증, 완료 receipt, 체크리스트 표시를 담당한다.

체크리스트 UI는 단순하게 유지한다.

```text
검증 완료 -> checked
검증 미완료 -> Start
```

사용자가 Start를 눌렀다고 완료되는 것이 아니다. Start는 설치, 복구, 연결 agent terminal을 여는 액션일 뿐이다. 완료는 자동 verifier 또는 setup agent가 Zebra-owned receipt를 쓰고, 체크리스트 store가 그 receipt를 읽어 검증했을 때만 생긴다.

main 기준 코드에서 중요한 제약:

- 체크리스트 snapshot에는 `isCompleted`, `isRunning`, `showsStart`만 있다.
- row UI에는 별도 상태 색상이나 "일부 완료" 상태가 없다.
- 현재 코드 TODO는 2번 GBrain 완료를 selected vault 스캔으로 처리하지 말라고 명시한다.
- 최종 2번 완료는 Zebra-owned GBrain setup receipt를 기준으로 해야 한다.
- selected vault가 있으면 Start flow의 launch directory이자 기본 source target 후보가 된다.
- selected vault가 없으면 home directory에서 agent terminal을 시작할 수 있다. 이때 home directory는 기본 launch directory일 뿐, 사용자 확인 없이 source target으로 간주하지 않는다.

## 핵심 변경

### Recorded Skill Runner

`zebra-gbrain-onboarding`은 installer가 아니라 workflow ledger다. Zebra 스크립트가 GBrain 설치 절차를 복제하지 않고, agent가 원문 문서를 따라가도록 하며 Zebra는 상태 기록과 검증을 맡는다.

CLI는 실제로 만들되, UI가 모든 helper를 직접 순서대로 호출하는 구조로 만들지 않는다. Start 액션의 단일 진입점은 `prompt`다.

```text
Swift Start action
  -> zebra-gbrain-onboarding prompt --selected-vault <path> --agent <selected>

setup agent
  -> zebra-gbrain-onboarding report ...
  -> zebra-gbrain-onboarding verify ...

internal/debug helper
  -> prepare / detect / status / next
```

- `prompt`
  - Zebra UI의 Start 액션이 호출하는 단일 진입점이다.
  - 내부에서 `prepare`, `detect`, `status`, `next`를 한 번 실행하거나 조합한다.
  - 현재 상태, 문서 snapshot, 다음 pending section, helper command 계약을 합쳐 selected primary agent에 주입할 startup prompt를 stdout으로 출력한다.
  - 완료 receipt를 쓰지 않는다. `state.json` 안의 receipt block은 `verify complete true`일 때만 기록한다.

- `prepare`
  - 최신 GBrain 문서 snapshot을 가져온다.
  - 기본 문서: `INSTALL_FOR_AGENTS.md`, `README.md`, `AGENTS.md`, `docs/GBRAIN_VERIFY.md`.
  - `skills/setup/SKILL.md`는 참고 문서로 가져올 수 있지만, Zebra의 완료 기준은 `INSTALL_FOR_AGENTS.md`다.
  - `INSTALL_FOR_AGENTS.md`의 `##` 섹션 단위 manifest와 hash를 만든다.

- `detect`
  - 현재 machine의 GBrain 전역 상태와, selected vault 또는 primary target이 가리키는 target 상태를 JSON으로 출력한다.
  - 확인 항목: CLI 또는 wrapper 후보, `~/.gbrain/config.json`, `gbrain doctor --json`, target의 `vaultPath`, `sourceId`, `profile`, source routing.
  - launch directory와 source target은 분리한다. home directory에서 시작해도 source target은 사용자가 명시적으로 선택하거나 생성한 brain repo여야 한다.

- `report`
  - agent가 section 시작, 완료, 실패, skip, 사용자 대기 상태를 기록할 때 호출한다.
  - agent는 state JSON을 직접 수정하지 않는다.

- `next`
  - manifest와 state 기준으로 다음 pending section을 반환한다.
  - 같은 hash로 이미 완료된 section은 skip 가능하다.
  - hash가 바뀐 section은 다시 확인 대상으로 표시한다.
  - 문서 commit이 바뀌면 새 manifest를 만들고 section hash를 비교한다. unchanged completed section은 `detect`가 여전히 만족할 때만 skip한다.
  - changed completed section은 다시 pending으로 되돌린다. 그 뒤 section은 내부적으로 downstream recheck 대상으로 표시하되 UI 상태를 새로 만들지는 않는다.

- `verify`
  - setup 완료 선언 가능 여부를 검사한다.
  - 결과는 색상 상태가 아니라 `complete: true | false`와 `reasons[]`로 출력한다.
  - `complete: true`일 때만 `state.json` 안의 `receipt.globalReadiness`와 resolved target entry를 완료 상태로 기록한다.

- `status`
  - Zebra UI가 읽을 수 있는 진행률과 상태 JSON을 출력한다.

### 상태와 Receipt

Zebra-owned onboarding state와 문서 snapshot은 Application Support 아래에 저장한다.

```text
~/Library/Application Support/zebra/onboarding/gbrain-setup-state.json
~/Library/Application Support/zebra/onboarding/gbrain-docs/<commit>/
```

`gbrain-setup-state.json`은 진행 상태와 완료 receipt를 함께 담는 단일 source of truth다. 파일을 `progress`용과 `receipt`용으로 나누지 않는다. 대신 같은 JSON 안에서 역할만 분리한다.

- `progress`: 중간 재개용 상태다. agent가 어디까지 진행했고, 어디서 멈췄고, 다음에 무엇을 해야 하는지 기록한다.
- `receipt`: 완료 판정 근거다. 체크리스트가 GBrain step을 checked로 표시해도 되는지 판단할 때만 사용한다.

체크리스트 완료 판정은 `receipt`를 보고 다시 검증한다. 중간 재개는 `progress`를 본다.

```text
schemaVersion
currentRunId
docsCommit
docsFetchedAt
selectedAgent
progress
  launchDirectory
  selectedVaultPath
  resolvedTargetKey
  targetResolution
    status
    method
    confirmedAt
  completedSections
  waitingForUser
  lastFailure
  nextSection
receipt
  globalReadiness
  primaryTargetKey
  targets
    <targetKey>
      vaultPath
      sourceId
      profileId
      gbrainExecutablePath 또는 wrapperPath
      doctorStatus
      sourcesCurrentResult
      searchProbeResult
      verifiedAt
      complete
      targetResolution
        method
        confirmedAt
      reasons
```

GBrain setup receipt는 체크리스트 완료의 기준이다. receipt는 별도 파일이 아니라 `gbrain-setup-state.json` 안의 `receipt` block이다. receipt에는 최소한 다음 의미가 있어야 한다.

```text
globalReadiness
primaryTargetKey
targets
  <targetKey>
    vaultPath
    sourceId
    profileId
    gbrainExecutablePath 또는 wrapperPath
    doctorStatus
    sourcesCurrentResult
    searchProbeResult
    verifiedAt
    complete
    targetResolution
      method
      confirmedAt
    reasons
```

`globalReadiness`와 `targets`는 분리해서 기록한다.

- `globalReadiness`: 이 컴퓨터에서 GBrain을 실행할 수 있는지.
- `primaryTargetKey`: selected vault가 없을 때 체크리스트 완료 판정에 사용할 마지막으로 명시 선택/생성된 brain repo target이다. home directory fallback이 아니다.
- `targets`: Zebra가 완료로 인정한 vault/source/profile 조합들. 여러 vault를 GBrain에 연결할 수 있으므로 단일 target이 아니라 map으로 둔다.
- `targetKey`: normalized vault path 기반의 stable key다. 같은 vault를 다시 setup하면 기존 target entry를 갱신하고, 다른 vault면 새 target entry를 추가한다.
- `targetResolution`: target이 어떻게 정해졌는지 기록한다. 허용 method는 `selected_vault`, `user_existing_repo`, `user_created_repo`, `user_confirmed_home`이다. `implicit_home`이나 `auto_discovered_candidate`는 허용하지 않는다.
- `doctorStatus`, `sourcesCurrentResult`, `searchProbeResult`: target별 검증 근거다. 여러 vault target이 있을 수 있으므로 전역 receipt가 아니라 각 target entry 안에 둔다.

이 분리가 필요하다. GBrain CLI는 전역 상태라 selected vault를 보지 않아도 판정할 수 있다. 반면 "Zebra가 사용할 vault/source/profile이 연결됐는지"는 selected vault가 있으면 그 vault의 target, selected vault가 없으면 `primaryTargetKey` target을 기준으로 검증해야 한다.

### 자동 체크리스트 검증

main 기준 체크리스트 구조는 이미 자동 refresh를 가진다. store는 앱 진입, selected vault 변경, email 연결 변경, 파일 watcher, 주기 timer에서 detected completion을 갱신한다. 이 구조는 유지한다.

다만 GBrain 완료 판정은 selected vault 직접 스캔이 아니라 Zebra-owned receipt 검증으로 바꾼다.

현재 임시 코드의 의도:

```text
steps 2/3은 selected vault 스캔으로 완료 처리하지 않는다.
step 2는 Zebra-owned GBrain setup receipt를 쓴다.
step 3은 resolved target의 adapter를 검증한다.
```

새 체크리스트 완료 규칙:

```text
gbrain row checked =
  GBrain setup receipt exists
  AND receipt.globalReadiness verifies
  AND resolved target exists
  AND target.complete == true
  AND target verifies

gbrain row Start =
  위 조건이 아니면 항상 Start
```

UI는 세부 상태를 나누지 않는다. 내부 진단 결과는 Start agent에게 넘길 context와 debug/tooltip 정보로만 쓴다.

### Target Resolution Guard

`INSTALL_FOR_AGENTS.md` Step 3은 사용자 파일 위치를 묻거나 새 brain repo를 만들라고 한다. Zebra는 이 원칙이 실제로 지켜지도록 prompt와 verifier 양쪽에서 강제한다.

허용되는 target 결정 방식:

```text
selected_vault
  -> selected vault가 있고, 그 vault를 기본 target 후보로 사용

user_existing_repo
  -> selected vault가 없거나 사용자가 다른 위치를 원해서 기존 markdown/brain repo 경로를 명시

user_created_repo
  -> 사용자가 새 brain repo 생성을 승인하고, 그 경로에서 git init 등 초기화

user_confirmed_home
  -> 사용자가 home directory를 brain repo target으로 명시 선택
```

허용하지 않는 방식:

```text
implicit_home
  -> selected vault가 없다는 이유만으로 home directory를 target으로 사용

auto_discovered_candidate
  -> setup skill Phase C의 repo discovery 결과 중 "best candidate"를 사용자 확인 없이 target으로 선택
```

Zebra prompt는 setup skill의 repo discovery를 완전히 금지하지 않는다. 다만 discovery 결과는 사용자에게 보여주는 후보일 뿐이고, target은 사용자 확인 뒤에만 resolved된다.

Verifier는 `targetResolution.method`가 허용 목록에 없으면 `target_not_resolved` 또는 `target_confirmation_missing`으로 실패해야 한다. resolved target이 없으면 import, sync, source registration, receipt write를 하지 않는다.

### 기존 설치 target discovery

preflight 에서 selected vault 가 없을 때 agent 가 `gbrain status --json` 결과를 직접 해석해 local brain repo path 를 추측하지 않는다. 먼저 Zebra helper 가 좁은 범위만 확인한다.

```text
zebra-gbrain-onboarding discover-existing-install-target
```

허용된 확인 범위:

```text
selectedVault
cached receipt / previous resolved target
gbrain status --json
gbrain sources current --json
gbrain sources list --json
```

금지된 확인 범위:

```text
broad filesystem search
home directory recursive scan
source repo clone/docs discovery
```

결과는 세 종류다.

```text
remote_thin_client
  -> remoteMCPURL 을 remote-only target 으로 인정
  -> local brain/vault repo path 를 묻지 않음
  -> nextAction.command = verify-existing-install --method thin_client_remote

local_vault
  -> targetPath 를 local vault target 으로 인정
  -> nextAction.command = verify-existing-install --target <path> ...

unresolved
  -> gbrain executable 은 있으나 좁은 확인 범위에서 local/PGLite brain repo target 을 못 찾음
  -> askUserFor = brain_repo_path
  -> 이때만 사용자에게 local brain/vault repo path 를 묻는다

fresh_install
  -> selectedVault 없음
  -> cached receipt / previous resolved target 없음
  -> remote thin-client evidence 없음
  -> gbrain executable 없음
  -> nextAction.command = prepare-source-repo --fresh-install
  -> 새 GBrain setup/install flow 로 진행한다
```

thin-client remote 는 local brain/vault repo 가 아예 없는 것이 정상일 수 있으므로, local path absence 를 실패로 보지 않는다. PGLite/local topology 에서는 local repo path 가 실제 target 이므로 gbrain executable 이 있는데 위 좁은 범위에서 못 찾으면 즉시 사용자에게 기존 local brain/vault repo path 를 묻는다. 반대로 gbrain executable 자체가 없고 selected vault / receipt / remote evidence 도 없으면 기존 설치 target unresolved 가 아니라 신규 설치 시작 상태로 본다. 이때 source repo 준비는 `prepare-source-repo --fresh-install` 이 맡고, brain/vault repo target 은 Step 3 에서 만들거나 선택한다.

### Verifier 검사 축

Verifier는 두 축을 분리한다.

```text
전역 실행 가능 신호
  gbrain --version
  또는 ~/.gbrain-profiles/*/gbrain-* --version
  selected vault 없이 검사 가능

receipt target 신호
  selected vault가 있으면 receipt.targets에서 해당 vaultPath target을 찾음
  selected vault가 없으면 receipt.primaryTargetKey target을 찾음
  setup 중 아직 resolved target이 없으면 INSTALL_FOR_AGENTS.md Step 3 기준으로 사용자에게 brain repo 위치를 묻거나 새 brain repo 생성을 확인
  targetResolution.method가 허용 목록인지 확인
  target.vaultPath 존재
  target.sourceId 존재
  .gbrain-source 또는 명시된 source/profile routing이 target과 일치
  gbrain sources current --json
  gbrain sources list --json
  source.local_path가 target.vaultPath와 일치

실제 사용 가능 신호
  gbrain doctor --json
  가능한 경우 exact keyword gbrain search/query roundtrip
  known text가 없으면 complete false reason에 남기고 Start로 보낸다
```

`.gbrain-source`는 기본 vault 연결 신호다. `.gbrain-mount`는 multi-brain routing 신호이므로 명시적인 mount topology에서만 보조 신호로 인정한다. `.gbrain-mount` 단독으로는 GBrain setup 완료로 보지 않는다.

### selected vault 변경 처리

selected vault가 바뀌면 체크리스트 refresh는 실행될 수 있다. 완료 판정은 selected vault를 직접 스캔해 즉석으로 완료 처리하지 않고, receipt target map에서 해당 vault에 대응하는 target을 찾아 검증한다.

정확한 동작:

```text
selected vault 변경
  -> checklist refresh 실행
  -> GBrain receipt가 있으면 receipt.targets에서 selected vault target을 찾음
  -> 해당 target이 있고 여전히 유효하면 checked 유지
  -> 해당 target이 없거나 검증 실패면 Start 표시
```

selected vault가 없을 때는 home directory에서 terminal agent를 시작할 수 있다. 그러나 home directory를 사용자 확인 없이 source target으로 쓰지 않는다. agent는 `INSTALL_FOR_AGENTS.md` Step 3처럼 사용자에게 기존 markdown/brain repo 위치를 묻거나 새 brain repo 생성을 확인해야 한다. 사용자가 home directory를 명시적으로 brain repo target으로 선택하면 그 선택은 허용한다.

```text
Start gbrain
  -> selected vault가 있으면 그 vault에서 시작하고 그 vault를 기본 target 후보로 사용
  -> selected vault가 없으면 home directory에서 시작하되 target unresolved 상태로 시작
  -> target unresolved이면 agent가 사용자에게 brain repo 위치를 묻거나 새 repo 생성을 확인
  -> setup agent가 resolved target을 결정하고 receipt.targets에 추가/갱신
  -> selected vault가 없는 최초 setup이면 resolved target을 receipt.primaryTargetKey로 기록
```

새 vault에서 setup이 완료되어도 기존 target을 덮어쓰지 않는다. 같은 `targetKey`가 있으면 갱신하고, 없으면 새 target을 추가한다.

### 체크리스트 UI 흐름

- 앱 진입 시 refresh한다.
- selected vault 변경 시 refresh한다.
- 관련 state 파일 변경 시 watcher가 refresh한다.
- 기존 주기 refresh는 유지한다.
- checked는 receipt 검증이 통과할 때만 표시한다.
- checked가 아니면 Start 버튼을 보여준다.
- Start 버튼은 완료 체크 버튼이 아니라 설치/복구/연결 agent terminal을 여는 버튼이다.
- 세부 실패 이유는 Start agent prompt/runtime packet에 포함한다.

GBrain row의 Start 액션은 단순 shell check가 아니라 recorded skill runner를 시작한다.

```text
Start gbrain
  -> zebra-gbrain-onboarding prompt --selected-vault <path> --agent <selected>
  -> prompt가 내부에서 prepare/detect/status/next 수행
  -> Swift가 stdout prompt를 selected primary agent에 주입
  -> agent가 INSTALL_FOR_AGENTS.md 원문 섹션 순서대로 설치/복구
  -> agent가 report로 진행 상태 기록
  -> agent가 완료 선언 전에 verify 호출
  -> verify complete true이면 state.json 안의 globalReadiness와 target entry 기록
  -> checklist가 다음 refresh에서 checked
```

### Prompt Packet Builder

`prompt` subcommand는 Prompt Packet Builder다. Swift는 `prepare`, `detect`, `status`, `next`를 각각 두 번 호출하지 않고 `prompt` 하나만 호출한다. `prompt`가 그 결과를 내부에서 모아 startup prompt를 만든다.

구성 순서:

```text
prompt
  -> prepare: 최신 GBrain docs snapshot 확보
  -> detect: 현재 machine/global 상태와 selected vault target 또는 primary target 상태 확인
  -> status: 현재 recorded runner 진행률 계산
  -> next: 다음 pending INSTALL_FOR_AGENTS.md ## section 계산
  -> render: agent startup prompt 출력
```

prompt packet에는 다음을 넣는다.

```text
role/contract
docs snapshot path와 docs commit
INSTALL_FOR_AGENTS.md ## section manifest/hash
current global GBrain state
existing receipt targets state
launch context: selected vault path if present, otherwise home directory
target context: selected vault target if present, otherwise unresolved until user chooses/creates a brain repo
resume context: completed/pending/waiting/lastFailure
next action hint
allowed helper commands: report, verify
```

launch/target 관련 문구는 agent를 헷갈리게 만들지 않도록 "이 vault가 틀렸다"처럼 단정하지 않는다. 예시는 다음처럼 쓴다.

```text
No completed GBrain receipt target exists for the current launch context yet.
Current launch directory: <launchDirectory>.
Do not treat this directory as verified until zebra-gbrain-onboarding verify succeeds.
```

selected vault가 없는 최초 setup에서는 `prompt`가 home directory launch prompt를 만든다. 이 prompt는 다음 제약을 반드시 포함한다.

```text
You are starting from the home directory only because no Zebra vault is selected.
Do not implicitly use the home directory itself as the GBrain source target.
The home directory is allowed only if the user explicitly confirms it as the brain repo target.
Before import, sync, source registration, or receipt write, resolve the brain repo target:
ask the user where their markdown/brain repo is, or ask whether to create a new brain repo.
If creating a new repo, use the path the user confirms, then run git init there if needed.
You may scan for candidate markdown repos, but candidates are suggestions only.
Do not choose or import a discovered candidate until the user confirms it.
```

문서가 달라졌을 때도 기본값은 전체 재설치가 아니다.

```text
docs commit changed
  -> 새 manifest 생성
  -> ## section hash 비교
  -> unchanged completed section은 detect가 여전히 만족하면 skip 가능
  -> changed completed section은 pending으로 되돌림
  -> 이후 section은 내부 downstream recheck 대상으로 표시
  -> UI는 checked/start 모델 유지
```

### Agent Prompt Injection

주력 terminal agent는 GBrain setup prompt를 처음부터 받은 상태로 실행한다. 이미 실행된 raw CLI session이 종료되기를 기다리는 구조로 만들지 않는다.

prompt 핵심:

```text
You are Zebra's GBrain setup agent.

Use the provided latest GBrain docs snapshot as source of truth.
Use INSTALL_FOR_AGENTS.md as the completion standard.
Do not reconstruct the docs into your own flow.
Follow the original ## section order unless detect/status proves a section is
already complete.
Before and after each section, call zebra-gbrain-onboarding report.
When user input is required, report waiting_for_user before asking.
Do not guess topology, API keys, search mode, or existing brain decisions.
Do not resolve the GBrain source target by implicit home directory or unconfirmed repo discovery.
Before import/sync/source registration/receipt write, ensure targetResolution is one of:
selected_vault, user_existing_repo, user_created_repo, user_confirmed_home.
Before declaring completion, call zebra-gbrain-onboarding verify.
If verify does not return complete true, do not say setup is complete.
```

runtime packet:

```text
RUN_ID
DOCS_COMMIT
DOCS_SNAPSHOT_DIR
STATE_FILE
CURRENT_STATUS
NEXT_SECTION
HELPER_COMMANDS
SELECTED_VAULT_PATH
LAUNCH_DIRECTORY
TARGET_CONTEXT
```

이 packet은 `zebra-gbrain-onboarding prompt`가 생성한다. agent 시작 전에 Swift가 helper command를 따로 여러 번 호출해 packet을 조립하지 않는다.

## 완료 판정

완료 기준은 `INSTALL_FOR_AGENTS.md`다. 다만 체크리스트 UI는 색상 상태를 만들지 않고 checked/start만 쓴다.

```text
checked 조건
  GBrain 실행 가능.
  doctor OK.
  search mode 확인 완료.
  resolved target의 targetResolution.method가 허용 목록에 있음.
  resolved target의 vault/source/profile 검증 완료.
  import/sync/search 또는 query roundtrip OK.
  Step 9 핵심 verification 통과.
  resolved receipt target complete true.

Start 조건
  checked 조건을 만족하지 않음.
```

Start 조건의 원인은 내부 `reasons[]`에 기록한다.

예:

```text
missing_gbrain_executable
doctor_failed
search_mode_unconfirmed
missing_receipt
receipt_target_missing
target_not_resolved
target_confirmation_missing
source_not_registered
source_local_path_mismatch
search_probe_failed
```

## 테스트 계획

- 이미 세팅된 사용자
  - selected vault가 있으면 해당 target 검증이 통과하고 GBrain row가 checked가 된다.
  - selected vault가 없으면 `receipt.primaryTargetKey` target 검증이 통과하고 GBrain row가 checked가 된다.

- GBrain CLI만 설치된 사용자
  - `globalReadiness`는 ready가 될 수 있다.
  - resolved target이 없으면 row는 checked가 아니며 Start를 보여준다.

- selected vault 없음 + target 미해결
  - GBrain row는 checked가 아니다.
  - Start 클릭은 home directory에서 agent terminal을 연다.
  - agent는 home directory를 암묵적으로 source target으로 쓰지 않고, 사용자에게 기존 brain repo 위치를 묻거나 새 brain repo 생성을 확인한다.
  - 사용자가 home directory를 명시적으로 brain repo target으로 선택하면 home directory target도 허용한다.
  - target이 resolved되기 전에는 import/sync/source registration/receipt write를 하지 않는다.

- repo discovery
  - setup skill Phase C의 scan 결과는 후보 목록으로만 사용한다.
  - 사용자가 후보를 확인하기 전에는 import/sync/source registration/receipt write를 하지 않는다.
  - verifier는 `auto_discovered_candidate` target을 완료로 인정하지 않는다.

- selected vault 변경
  - selected vault에 대응하는 receipt target이 있고 유효하면 checked가 유지된다.
  - selected vault에 대응하는 receipt target이 없으면 기존 다른 vault target이 유효해도 현재 row는 checked가 아니며 Start를 보여준다.
  - selected vault 변경만으로 새 vault를 스캔해 checked로 만들지 않는다.

- 여러 vault target
  - 새 vault setup 완료 시 `receipt.targets`에 새 target을 추가한다.
  - 기존 vault target은 같은 `targetKey`를 갱신하는 경우가 아니면 덮어쓰지 않는다.

- 미설치 사용자
  - CLI/wrapper가 없으면 checked가 아니며 Start 버튼이 보인다.
  - selected vault가 있으면 Start 클릭은 완료 처리하지 않고 agent terminal만 연다.
  - selected vault가 없으면 Start 클릭은 home directory에서 agent terminal을 열고, agent가 target 선택/생성을 먼저 물어본다.

- 잘못된 receipt target
  - receipt target source의 `local_path`가 target vault와 다르면 checked가 아니다.

- doctor 실패
  - CLI가 있어도 `gbrain doctor --json` 실패 시 checked가 아니다.

- search 실패
  - doctor OK여도 search/query roundtrip 실패 시 checked가 아니다.

- resume
  - 중단 후 재실행하면 같은 hash로 완료된 section은 skip하고 다음 pending section부터 이어간다.

- 문서 변경
  - docs snapshot section hash가 바뀌면 해당 section은 changed로 표시하고 다시 확인한다.

## 가정

- Zebra v1 완료 기준은 `INSTALL_FOR_AGENTS.md`다.
- `skills/setup/SKILL.md`는 참고 문서지만, cold-start 같은 더 강한 운영 기준은 체크리스트 필수 완료 조건에 넣지 않는다.
- GBrain CLI 설치 여부는 전역 상태다.
- 체크리스트 완료 여부는 selected vault 직접 스캔이 아니라 Zebra-owned receipt targets 검증으로 결정한다.
- selected vault가 있으면 GBrain setup Start flow의 launch directory이자 기본 target 후보가 된다.
- selected vault가 없으면 최초 GBrain setup agent는 home directory에서 시작할 수 있지만, home directory를 사용자 확인 없이 source target으로 쓰지 않는다.
- 사용자가 home directory를 명시적으로 brain repo target으로 선택하면 home directory target도 허용한다.
- selected vault가 없는 최초 setup은 `INSTALL_FOR_AGENTS.md` Step 3처럼 사용자에게 brain repo 위치를 묻거나 새 brain repo 생성을 확인한 뒤 resolved target으로 진행한다.
- `.gbrain-source`가 기본 vault 연결 신호다.
- `~/.gbrain-profiles/*/gbrain-*` wrapper는 Zebra-owned 실행 신호일 수 있지만, 단독 완료 증명은 아니다.
- 기존 체크리스트 UI의 checked/start 모델은 유지한다.

## 구현 참고

- 현재 체크리스트/store 구조:
  `Packages/ZebraVault/Sources/ZebraVault/AgentOnboarding/ZebraOnboardingChecklist.swift`
- 현재 sidebar refresh/start wiring:
  `Sources/Zebra/Sidebar/ZebraSidebarBody.swift`
- GBrain source routing model:
  `/Users/han/gbrain/docs/architecture/brains-and-sources.md`
- GBrain 설치 기준:
  `/Users/han/gbrain/INSTALL_FOR_AGENTS.md`
