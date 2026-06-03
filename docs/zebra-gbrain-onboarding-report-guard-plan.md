# Zebra GBrain 온보딩 Report Guard 설계

[Source: Codex/Zebra planning conversation, 2026-06-03]

## 요약

Zebra GBrain 온보딩은 agent가 최신 `INSTALL_FOR_AGENTS.md` 원문을 읽고 설치를 진행하고, `zebra-gbrain-onboarding` helper가 진행 기록과 완료 검증을 담당하는 구조다. 이 문서는 agent가 brain repo target 확정 전 `Step 3.5`나 `Step 4`를 먼저 진행하는 문제를 막기 위한 report guard 설계를 정리한다.

핵심 원칙은 두 가지다.

```text
Zebra가 아는 구간
-> deterministic role mapping + hard guard로 막음

Zebra가 모르는 구간
-> agent가 원문을 읽고 role mapping을 제안할 수 있음
-> helper는 그 판단을 기록하고 진행을 허용할 수 있음
-> 단, final checked/receipt는 live verify 통과 전에는 허용하지 않음
```

## 배경

현재 책임 분리는 다음과 같다.

```text
INSTALL_FOR_AGENTS.md
-> 설치 기준 원문

Zebra startup prompt
-> agent에게 현재 state, docs snapshot, helper 사용법, guard 규칙 전달

setup agent
-> 실제 설치 명령 실행
-> 사용자 질문
-> 단계별 report 호출
-> 완료 전 verify 호출

zebra-gbrain-onboarding helper
-> report/status/verify 제공
-> state.json 업데이트
-> receipt 기록
-> checklist 완료 판정 근거 제공
```

helper는 installer가 아니다. 설치 판단과 명령 실행은 agent가 한다. 하지만 helper는 잘못된 진행 보고를 Zebra 공식 상태로 인정하면 안 된다.

원문 기준으로 brain repo target은 `Step 3: Create the Brain` 안에서 확정되어야 한다.
현재 대조 기준은 `/Users/han/gbrain/INSTALL_FOR_AGENTS.md` VERSION `0.42.8.0`이다.

```text
Step 3
-> gbrain init
-> gbrain doctor --json
-> 사용자 markdown/brain repo 위치 질문 또는 새 brain repo 생성

Step 3.5
-> conservative / balanced / tokenmax 선택
-> gbrain config set search.mode <mode>
-> gbrain search modes

Step 4
-> import / embed / query
```

따라서 target 미확정 상태에서 `Step 3.5 started`, `Step 4 started`, `Step 4 completed`가 성공 기록으로 남으면 안 된다.

## Section Role Mapping

Zebra는 최신 `INSTALL_FOR_AGENTS.md`를 `##` 섹션 단위로 나누고 각 섹션에 대해 manifest를 만든다.

```text
title
normalizedTitle
bodyHash
body
orderIndex
detectedRole
roleSource
roleConfidence
roleEvidence
```

role은 Zebra 내부 guard용 의미 이름이다.

```text
install
credentials
create_brain
search_mode
import_index
verify
non_role
unknown
```

실제 원문에는 guard role을 갖지 않는 섹션도 있다. 이 섹션들은 설치 문서의 일부이지만 Zebra checklist gate를 여는 역할은 아니다.

```text
Step 0: If you are not Claude Code
Step 4.5: Wire the Knowledge Graph
Step 5: Load Skills
Step 6: Identity (optional)
Step 7: Recurring Jobs
Step 8: Integrations
Upgrade
v0.42.0+ onboard surface (NEW)
```

이 섹션들은 `gbrain embed --stale`, `gbrain doctor --json`, `gbrain config set search.mode`, `tokenmax` 같은 토큰을 재사용할 수 있다. 따라서 command signature가 일부 맞더라도 `non_role`로 먼저 흡수하고, `install/create_brain/search_mode/import_index` 같은 gate role을 부여하지 않는다.

매핑 우선순위는 다음이다.

```text
1. known hash mapping
2. exact/normalized title mapping
3. deterministic command signature mapping
4. order/context sanity check
5. agent-assisted mapping
```

`known hash mapping`은 Zebra가 이전에 안전하게 인식한 section body hash를 같은 role로 재사용하는 방식이다. 문서가 바뀌지 않은 경우 가장 신뢰도가 높다.

`exact/normalized title mapping`은 현재 알려진 제목을 정규화해서 매핑한다. 정규화는 `(DO NOT SKIP)`, `(optional)`, `(NEW)` 같은 괄호 접미사를 제거한 뒤 비교한다.

```text
Step 1: Install GBrain -> install
Step 2: API Keys -> credentials
Step 3: Create the Brain -> create_brain
Step 3.5: Confirm search mode with the user -> search_mode
Step 4: Import and Index -> import_index
Step 9: Verify -> verify
```

`deterministic command signature mapping`은 본문에서 명령어와 필수 토큰 조합을 확인한다. 자연어 유사도는 쓰지 않는다.

```text
install
-> gbrain --version
-> bun install -g github:garrytan/gbrain

credentials
-> ZEROENTROPY_API_KEY
-> OPENAI_API_KEY
-> ANTHROPIC_API_KEY

create_brain
-> gbrain init
-> gbrain doctor --json
-> brain repo
-> markdown files
-> Ask the user where their files are

search_mode
-> conservative
-> balanced
-> tokenmax
-> gbrain config set search.mode
-> gbrain search modes

import_index
-> gbrain import
-> gbrain embed --stale

verify
-> docs/GBRAIN_VERIFY.md
-> verification checks
```

`order/context sanity check`은 signature가 맞아도 말이 안 되는 매핑을 막는다. 예를 들어 `search_mode`는 `create_brain`보다 앞에 있으면 낮은 confidence로 처리하고, `import_index`는 `create_brain` 뒤에 있어야 한다.

deterministic mapping이 실패하거나 confidence가 낮으면 `agent-assisted mapping`으로 넘어간다. agent는 원문을 읽고 section role을 제안할 수 있다.

```bash
zebra-gbrain-onboarding report \
  --status mapped_role \
  --section "Step X: ..." \
  --role search_mode \
  --evidence "contains conservative/balanced/tokenmax and gbrain search modes"
```

helper는 agent 판단을 그대로 완료 판정으로 쓰지 않는다. 다만 section role mapping으로 기록하고, 이후 concrete guard는 계속 적용한다.

```text
roleSource = agent_judgment
roleConfidence = agent_asserted
roleEvidence = agent-provided evidence
sectionHash = current body hash
```

## Report Guard 로직

`zebra-gbrain-onboarding report`는 state와 section role을 확인한 뒤, `status + role` 조합이 현재 상태에서 허용되는지 검사한다.

Hard reject 대상:

```text
install completed
-> gbrain --version 실패 시 거부

create_brain completed
-> gbrain init/doctor 실패 시 거부
-> brain repo target 미확정 시 거부
-> targetResolution.method가 허용 목록이 아니면 거부
-> target이 implicit home이면 거부
-> target이 ~/gbrain tool repo이면 거부

search_mode started/completed
-> create_brain completed 전이면 거부
-> brain repo target 미확정이면 거부

search_mode completed
-> 위 조건을 만족해도 `gbrain config get search.mode`가 conservative / balanced / tokenmax 중 하나를 반환하지 않으면 거부
-> agent-assisted mapping으로 search_mode 라벨을 붙였더라도 실제 config가 없으면 거부

import_index started
-> create_brain completed 전이면 거부
-> search_mode completed 전이면 거부
-> brain repo target 미확정이면 거부

import_index completed
-> create_brain completed 전이면 거부
-> search_mode completed 전이면 거부
-> brain repo target 미확정이면 거부
-> source 등록 없음이면 거부
-> target/source path 불일치면 거부

verify completed
-> verify complete true가 아니면 거부
```

체크리스트 자동 완료 판정도 같은 경계를 따라야 한다. 진행 중인 run(`currentRunId` 또는 `progress`)이 있는 경우에는 live verifier가 source/doctor를 통과하더라도 `import_index` 역할의 Step 4 완료 report가 trusted progress에 남기 전까지 UI를 checked로 올리지 않는다. 이미 설치가 끝난 기존 사용자의 stale receipt처럼 active progress가 없는 경우에는 기존대로 live verifier가 receipt를 복구할 수 있다.

`waitingForUser`가 설정된 상태에서는 체크리스트 자동 완료 판정이 `gbrain doctor`, `gbrain sources current`, `gbrain sources list` 같은 live probe를 반복 실행하면 안 된다. 사용자 결정을 기다리는 동안은 setup이 완료될 수 없으므로 즉시 incomplete를 반환한다. 또한 live verifier가 통과한 뒤 receipt를 갱신할 때는 `verifiedAt` 같은 timestamp만 바뀐 경우 state 파일을 다시 쓰지 않는다. 그렇지 않으면 state write -> file watcher refresh -> live verify -> state write 루프가 생겨 CPU/fseventsd 부하가 커진다.

`--target`, `--method`, `--profile-id` 같은 target 확정용 flags는 `create_brain completed` report에서만 state/receipt에 반영한다. 다른 section report에 붙은 target flags는 target을 확정하지 않고 거부한다. `source-id`는 import/source 검증용 보조 입력으로만 사용할 수 있고, 단독으로 target을 확정하지 않는다.

거부 시 helper는 report를 성공 상태로 기록하지 않는다.

```json
{
  "ok": false,
  "reason": "brain_repo_target_unresolved",
  "section": "Step 4: Import and Index",
  "status": "started",
  "nextAction": "report waiting_for_user for brain_repo_target_resolution"
}
```

`waiting_for_user`는 허용한다. 다만 invalid `started/completed` report가 기존 `waitingForUser`를 지우면 안 된다. 또한 unrelated successful report도 기존 `waitingForUser`를 지우면 안 된다.

```text
waitingForUser = brain_repo_target_resolution
-> Step 1 completed 성공
-> 여전히 brain_repo_target_resolution 유지

waitingForUser = brain_repo_target_resolution
-> create_brain completed + --target + --method 성공
-> brain_repo_target_resolution 해제
```

대표 waiting reason:

```text
topology_resolution
brain_repo_target_resolution
credential_resolution
search_mode_resolution
embedding_resolution
section_role_mapping_resolution
```

unknown role인 경우 agent 진행 자체는 막지 않는다. 대신 trusted completion으로 인정하지 않는다.

```text
unknown role completed
-> report 자체를 거부
-> completedSections에는 넣지 않음
-> helper가 agent-assisted mapping 요청 nextAction을 반환
-> 최종 checked/receipt는 verify complete true로만 가능
```

## 완료 검증과 체크리스트

이미 GBrain이 정상 설치된 사용자는 setup flow를 다시 탈 필요가 없다. Zebra 진입, vault 변경, profile 변경, checklist refresh 시 live verifier가 자동으로 검사한다.

checked 조건:

```text
gbrain executable exists
AND gbrain doctor passes
AND receipt target exists for selected vault or primary target
AND source current/list matches target path
AND target.complete == true after live verification
```

state/receipt가 없거나 stale이어도 live verifier가 실제 상태를 확인해 complete true를 쓸 수 있으면 checked 처리한다.

Start 버튼은 다음 경우에만 설치/복구 agent terminal을 연다.

```text
gbrain missing
doctor failed
receipt missing
target missing
source not registered
source path mismatch
verify incomplete
```

## 테스트 계획

Unit tests:

```text
report completed install rejects when fake gbrain --version fails
report completed create_brain rejects when target unresolved
report started search_mode rejects before create_brain complete
report completed search_mode rejects when `gbrain config get search.mode` is unset
report started import_index rejects before search_mode complete
report completed import_index rejects before search_mode complete
report completed import_index rejects when source list has no matching local_path
report completed verify rejects unless verify complete true
waiting_for_user does not get cleared by invalid started/completed report
waiting_for_user does not get cleared by unrelated successful report
target flags outside `create_brain completed` are rejected and do not mutate target state
unknown role does not create trusted completed progress
agent-assisted role mapping records roleSource=agent_judgment
agent-assisted role mapping still respects concrete prerequisites
Step 7 / Upgrade token reuse sections do not map to guarded roles
```

Mapping tests:

```text
known hash maps to expected role
exact title maps to expected role
command signature maps renamed section to expected role
ambiguous signature stays unknown
bad order lowers confidence or stays unknown
changed section hash invalidates stale completed section
```

Prompt/state tests:

```text
no selected vault first launch
-> waitingForUser == topology_resolution
-> prompt asks only topology

after topology/init/doctor
-> waitingForUser == brain_repo_target_resolution
-> prompt asks only brain repo target

target unresolved
-> prompt forbids search_mode/import progress

target resolved + create_brain complete
-> search_mode may start

brain_repo_target_resolution pending + unrelated section completed
-> waitingForUser remains brain_repo_target_resolution

target flags on non-create_brain report
-> rejected with target_flags_not_allowed
-> resolvedTargetKey remains unset
```

End-to-end smoke test:

```text
fake gbrain executable
fake docs snapshot
temporary state.json
simulate report calls in wrong order
assert helper rejects unsafe progress
simulate agent-assisted role mapping
assert helper accepts mapping but still enforces prerequisites
simulate correct order
assert verify can complete receipt
```

## 전제

- `INSTALL_FOR_AGENTS.md`가 Zebra 완료 기준이다.
- `skills/setup/SKILL.md`는 prompt wording에는 참고할 수 있지만 completion order를 덮어쓰지 않는다.
- section title/hash는 GBrain 업데이트에 따라 바뀔 수 있으므로 guard는 exact string에만 의존하지 않는다.
- deterministic mapping 실패 시 agent-assisted mapping을 허용한다.
- agent-assisted mapping은 section role 해석에만 사용하고, 실제 설치 상태와 최종 완료 판정은 helper/verifier가 검증한다.
- Step 7 recurring jobs와 Step 8 integrations는 제품 범위가 "full INSTALL_FOR_AGENTS completed"로 바뀌지 않는 한 최소 Zebra checklist checked 조건에는 포함하지 않는다.
