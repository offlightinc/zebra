---
title: "Zebra 온보딩 이메일 연동 플랜"
status: implemented
last_verified: 2026-07-14
related:
  - /Users/han/brain-offlight/tasks/zebra-onboarding-email-connection.md
  - /Users/han/brain-offlight/tasks/zebra-clawvisor-agent-onboarding-flow.md
  - /Users/han/brain-offlight/tasks/zebra-clawvisor-coming-soon-agents-wire-up.md
---

# Zebra 온보딩 이메일 연동 플랜

## 2026-07-14 구현 상태

Gmail 연결의 canonical 완료 계약은 `CLAWVISOR_URL`,
`CLAWVISOR_AGENT_TOKEN`, `CLAWVISOR_TASK_ID` 세 key와
`zebra-source-onboarding gmail verify-env`, `verify-connection`의 연속 성공이다.
아래 2026-06-09 초안에 남아 있는 네 key/agent별 integration flow 설명보다 이 절의
현재 구현을 우선한다.

첫 안내는 모든 사용자에게 기존 `Clawvisor 로그인 → Agents → GBrain` wizard를
보여준다. 안내 마지막에만 GBrain 항목이 보이지 않는지 묻고, No이면 기존 흐름을
그대로 계속한다. Yes이면 그 응답에서는 분기만 확인하고 다음 turn에서만
`Agents → Other agent`의 로그인 계정 전용 setup prompt 전체를 현재 Zebra terminal
agent에 붙여넣도록 안내한다. Zebra는 `user_id`를 추측하거나 별도로 요구하지 않는다.

Other agent fallback 뒤 Zebra-owned setup packet은 Clawvisor catalog에서 Gmail,
Google Calendar, Google Contacts를 확인하고, 미연결 서비스의 Accounts OAuth 완료 뒤
catalog를 재조회한다. catalog가 반환한 활성 service identifier를 그대로 사용해
GBrain용 standing task를 만들고 승인된 task ID를 확보한다. 이어 canonical 세 key를
`~/.gbrain/.env`에 unrelated line 보존 방식으로 upsert하고 권한을 제한한다. 사용자에게
account alias, curl, JSON 수정, env 직접 편집, chmod를 요구하지 않는다.

Source Onboarding state와 helper stdout에는 `user_id`, agent token, task ID를 저장하거나
출력하지 않는다. Gmail 완료 상태는 env 검증과 실제 Clawvisor task/Gmail gateway
검증이 모두 성공한 뒤에만 기록된다. 구현은 기존 setup packet/state/helper 경로인
`ZebraSourceOnboardingGmailCommand`와 `ZebraSourceOnboardingHelper`를 재사용한다.

## 최신 handoff 메모

이 문서는 2026-06-09 최신 대화까지 반영한 handoff 기준 문서다. 이전 세션은
`Selected model is at capacity. Please try a different model.` 메시지 때문에 중간에
끊겼고, 다음 세션은 이 문서를 최신 결정의 source of truth로 삼아 이어서 작업하면
된다. 특히 아래 세 가지가 최신 결정이다. [Source: User, conversation, 2026-06-09]

- 이메일 onboarding은 setup packet + state file + helper command를 추가해 중간 단계와
  재개 상태를 기록한다.
- flow 분기는 primary agent 하나만 보지 않고, GBrain runtime receipt의
  `openclaw`/`hermes` 결과를 함께 본다.
- `runtime == openclaw`이면 Clawvisor email flow는 OpenClaw integration target으로
  간다. `runtime == hermes`이면 Hermes target으로 가지 않고, primary agent 기준의
  Claude Code 또는 generic agent flow로 간다.

## 결론

### 방향

Zebra 온보딩의 이메일 단계는 새 OAuth 흐름이나 별도 연결 UI를 만들 필요가 없다.
이미 이메일 사이드바의 Gmail Connect 흐름이 Clawvisor onboarding, agent terminal
placement, retry/repair 상태를 갖고 있으므로, 온보딩의 Start 버튼은 같은 연결
계약을 써야 한다. 사이드바에서 시작했든 체크리스트에서 시작했든 결과는 하나다.
Clawvisor Gmail standing task가 준비되면 이메일 체크리스트 step은 완료로 떠야
한다. [Source: User, conversation, 2026-06-02; Source:
Sources/Zebra/Sidebar/ZebraSidebarBody.swift, 2026-06-02]

현재 브랜치에서 체크리스트 agent step은 이미 `openZebraAgentTerminal`을 통해 agent
terminal로 뜨도록 고쳐져 있다. 그래서 이번 작업의 핵심은 terminal placement 자체가
아니라 `.email` step의 command, prompt, agent 선택, completion 계약을 정리하는
것이다.

### 범위

이번 작업은 Claude Code 전용으로 묶여 있는 Clawvisor 이메일 onboarding을
primary local agent와 GBrain runtime receipt를 함께 보는 flow로 바꾸는 데까지
포함한다. 여기서 primary agent는 사용자가 대화하는 terminal agent이고,
GBrain runtime은 2단계에서 선택/검증된 OpenClaw 또는 Hermes 실행 도구다. 두 축을
섞으면 안 된다. [Source:
Packages/ZebraVault/Sources/ZebraVault/MarkdownChatPill/MarkdownPillAgent.swift,
2026-06-09; Source:
Packages/ZebraVault/Sources/ZebraVault/AgentOnboarding/ZebraGBrainRuntimeOnboarding.swift,
2026-06-09]

GBrain runtime receipt가 `openclaw`이면 Clawvisor 이메일 연결 target은 OpenClaw로
잡는다. 이 경우 대화와 실행을 안내하는 terminal은 primary agent이지만, setup packet의
절차는 Clawvisor OpenClaw integration guide를 따른다. GBrain runtime receipt가
`hermes`이거나 runtime receipt가 없으면 Clawvisor 연결 target은 primary agent 기준으로
정한다. primary agent가 Claude면 Claude Code flow, Codex/Antigravity면 generic agent
flow다. Hermes는 GBrain runtime으로는 지원하지만, 현재 확인한 범위에서 Clawvisor email
integration target으로 직접 쓰지 않는다. [Source: Clawvisor OpenClaw Integration
Guide, https://raw.githubusercontent.com/clawvisor/clawvisor/main/docs/INTEGRATE_OPENCLAW.md,
2026-06-09; Source: Clawvisor Generic Agent Integration Guide,
https://raw.githubusercontent.com/clawvisor/clawvisor/main/docs/INTEGRATE_GENERIC.md,
2026-06-09]

기존 sidebar agent picker 모델은 제거하고, 이미 정해진 primary agent 결과만 사용한다.
또한 긴 inline prompt만으로 진행하지 않고, GBrain setup처럼 setup packet과 state file을
만들어 단계별 진행을 기록하고 나중에 이어서 시작할 수 있게 한다. 완료의 source of
truth는 여전히 `~/.gbrain/.env`와 repair state다. setup state는 재개와 안내용이지,
이메일 연결 완료 자체를 대체하지 않는다.

## 현재 main 기준

### 이미 들어온 변경

현재 main에는 온보딩 체크리스트의 agent-backed step을 terminal registry로
라우팅하는 변경이 들어와 있다. `startOnboardingChecklistStep`은 `.agent`,
`.adapter`, `.email`, `.ingest`, `.goals`처럼 agent가 필요한 step에서
`workspace.openZebraAgentTerminal(...)`을 호출하고, source를
`.onboardingChecklist(stepID)`로 남긴다. 이 덕분에 체크리스트에서 띄운 agent
terminal도 ChatPill/brain-sync agent terminal과 같은 companion pane 정책의
대상이다. [Source: Sources/Zebra/Sidebar/ZebraSidebarBody.swift, 2026-06-02;
Source:
Packages/ZebraVault/Sources/ZebraVault/AgentTerminal/ZebraAgentTerminalRegistry.swift,
2026-06-02]

또한 최신 main의 `zebra-agent-onboarding`은 primary agent 설치 실패, 재개,
다른 agent 선택을 처리하는 recovery 흐름을 갖고 있다. 이메일 연동 단계가 이
installer/recovery UX를 다시 만들면 중복이다. 이메일 단계는 이미 선택된
primary agent를 존중하고, primary agent가 없거나 준비되지 않은 경우에는 agent
CLI scan/onboarding 단계를 먼저 완료하도록 안내하는 편이 맞다. [Source:
Resources/zebra-agent-onboarding, 2026-06-02; Source:
tests/test_zebra_agent_onboarding_resume.sh, 2026-06-02]

### 설계 결정

온보딩 이메일 Start를 사이드바의 `startClawvisorOnboardingAgent`에 그대로 연결하는
방식은 조심해야 한다. 호출만 공유하면 코드 경로는 단순해지지만, 체크리스트의
row/running state와 sidebar의 connect/repair state가 섞일 수 있다. 따라서 공유 범위는
함수 전체가 아니라 아래 command builder로 제한한다.

terminal source는 entrypoint별로 유지한다. sidebar Gmail Connect는 기존처럼
`.onboardingChecklist(.sourceOnboarding)`이고, checklist Email Start는 `.onboardingChecklist(.email)`이다.
대신 둘 다 `openZebraAgentTerminal(...)`로 열고 agent metadata를 남겨서 agent
panel/companion panel 정책의 대상이 되게 한다. `ZebraOnboardingChecklistStepID.email`은
체크리스트 UI의 row/running state와 start dispatch에 쓰고, 이메일 연결 완료 판정에는
쓰지 않는다.

## 구현 방향

### Entry point와 terminal source

첫 번째 작업은 `.email` checklist step과 sidebar Gmail Connect가 같은 연결
계약을 사용하도록 하는 것이다. 구체적으로는 launch command 생성,
primary agent 해석, Clawvisor 안내 prompt, 연결 완료 판정을 별도 helper나
command builder로 묶는다. 두 entrypoint는 이 builder 결과를 받아 쓰지만, 자기 UI
상태와 terminal source는 각자 유지한다.

정리하면 연결 계약은 하나이고, entrypoint와 terminal source는 둘이다.

- Sidebar Gmail Connect: 이메일 사이드바에서 Clawvisor Gmail 연결을 시작한다.
  terminal source는 `.onboardingChecklist(.sourceOnboarding)`으로 둔다.
- Checklist Email Start: 온보딩 row에서 같은 Clawvisor Gmail 연결을 시작한다.
  terminal source는 `.onboardingChecklist(.email)`로 둔다.
- Agent panel 인식: 둘 다 `openZebraAgentTerminal(...)`로 열고 agent metadata를 남긴다.
- Shared builder: prompt, primary agent 해석, cwd, env write target만 공유한다.
- Checklist step ID: `.email` row의 running/active/completed UI 상태에만 쓴다.

### Primary agent 사용

사이드바도 더 이상 "Connect 버튼 아래 agent picker에서 선택한 agent"를 중심으로
생각하지 않는다. Zebra onboarding의 첫 단계에서 주력 agent가 이미 정해졌다는
전제를 둔다. 따라서 sidebar Gmail Connect를 눌러도 기본 동작은 primary agent로
즉시 시작하는 것이다. primary agent가 없거나 준비되지 않은 경우에만 agent CLI
onboarding으로 돌려보내거나, 최소한의 fallback 선택 UI를 보여준다. 이렇게 해야
온보딩 체크리스트와 사이드바가 서로 다른 agent 선택 모델을 갖지 않는다. [Source:
User, conversation, 2026-06-02; Source:
Packages/ZebraVault/Sources/ZebraVault/AgentOnboarding/ZebraAgentPreferenceStore.swift,
2026-06-02]

primary agent가 없거나 준비되지 않은 경우에는 이메일 단계가 installer를 직접 열지
않는다. 이때는 agent CLI scan/onboarding 단계를 먼저 완료하도록 안내한다.
`zebra-agent-onboarding`은 agent 선택과 복구를 담당하고, 이메일 onboarding은 그 결과를
사용하는 쪽에 머무른다.

### GBrain runtime에 따른 flow 분기

이메일 onboarding은 primary agent만 보지 않는다. GBrain runtime 2단계가 이미 끝났다면
`ZebraGBrainRuntimeOnboardingStore().selectedRuntimeForGBrainSetup()`으로 runtime
receipt를 읽고, 그 결과를 Clawvisor 연결 target 결정에 반영한다. [Source:
Packages/ZebraVault/Sources/ZebraVault/AgentOnboarding/ZebraGBrainRuntimeOnboarding.swift,
2026-06-09]

분기 규칙은 단순하게 둔다.

```text
if selectedRuntime == openclaw:
    flowKind = openClaw
else if primaryAgent == claude:
    flowKind = claudeCode
else:
    flowKind = genericAgent
```

여기서 `openClaw`는 OpenClaw가 terminal agent라는 뜻이 아니다. 사용자는 계속 primary
agent 터미널에서 안내를 받는다. 다만 setup packet이 지시하는 Clawvisor 설치 target이
OpenClaw라는 뜻이다. `hermes` runtime은 GBrain 실행 도구로만 취급하고, Clawvisor
이메일 연결 target으로 직접 쓰지 않는다. 따라서 `runtime == hermes`는 primary agent
기준의 Claude Code 또는 generic agent flow로 간다.

### Flow case matrix

| Primary agent | GBrain runtime receipt | Clawvisor email flow |
| --- | --- | --- |
| Claude | none | Claude Code flow |
| Codex | none | Generic agent flow via Codex |
| Antigravity | none | Generic agent flow via Antigravity |
| Claude | OpenClaw | OpenClaw integration flow, guided by Claude |
| Codex | OpenClaw | OpenClaw integration flow, guided by Codex |
| Antigravity | OpenClaw | OpenClaw integration flow, guided by Antigravity |
| Claude | Hermes | Claude Code flow |
| Codex | Hermes | Generic agent flow via Codex |
| Antigravity | Hermes | Generic agent flow via Antigravity |

### Setup packet과 state file

현재 이메일 onboarding은 agent prompt가 "어느 단계까지 했는지 물어봐라"라고 안내할
뿐, Zebra가 읽는 진행 상태 파일은 없다. 이 방식은 사용자가 중간에 닫았다가 나중에
다시 시작할 때 agent 기억에 의존한다. GBrain setup과 같은 방식으로 이메일 전용
setup packet과 state file을 추가한다. [Source:
Packages/ZebraVault/Sources/ZebraVault/AgentOnboarding/ZebraGBrainOnboarding.swift,
2026-06-09]

저장 위치는 Zebra onboarding directory 아래로 둔다.

```text
~/Library/Application Support/zebra/onboarding/source-onboarding-state.json
~/Library/Application Support/zebra/onboarding/source-onboarding-gmail-setup-packets/<run-id>.md
~/Library/Application Support/zebra/onboarding/bin/zebra-source-onboarding
```

state file에는 secret을 저장하지 않는다. `CLAWVISOR_AGENT_TOKEN` 값, Gmail token,
Clawvisor callback secret 같은 민감값은 기록하지 않는다. Gmail 진행 결과는
`sourceReadiness.gmail`에 기록하고, helper command는 `zebra-source-onboarding gmail ...`
형태로 실행한다.

setup packet은 매 launch마다 새로 쓰고 0600 권한으로 보호한다. packet은 현재
`flowKind`, 현재 완료된 section, 다음 section, 완료 기준, report command, env write
target을 담는다. terminal에 주입하는 첫 prompt는 GBrain처럼 짧게 유지한다. 첫 응답에서
사용자에게 setup이 시작됐다고 말하고, packet 경로를 읽은 뒤 packet을 authoritative
instruction으로 따르게 한다.

helper command는 최소 기능만 둔다.

```text
zebra-source-onboarding gmail report --status started --section "<section title>"
zebra-source-onboarding gmail report --status completed --section "<section title>"
zebra-source-onboarding gmail report --status waiting_for_user --section "<section title>" --note "<what is needed>"
zebra-source-onboarding gmail report --status failed --section "<section title>" --note "<reason>"
zebra-source-onboarding gmail status
zebra-source-onboarding gmail verify-env
```

`verify-env`는 `~/.gbrain/.env`의 네 key 존재와 형식만 확인한다. 실제 Gmail 사용 가능
여부는 기존 email client refresh/repair state가 판단한다.

### 완료 판정

완료 판정은 새로 정의하지 않는다. Zebra 이메일 클라이언트는 `~/.gbrain/.env`에서
`CLAWVISOR_URL`, `CLAWVISOR_AGENT_TOKEN`, `CLAWVISOR_GMAIL_TASK_ID`,
`ZEBRA_CLAWVISOR_GMAIL_ACCOUNT`를 읽고, 체크리스트는 이 env key 조합과
`emailConnectionRepairState == nil`을 기준으로 이메일 단계를 완료 처리한다. 이 경로가
이미 있으므로, 새 flow도 같은 파일을 쓰게 해야 한다. [Source:
Packages/ZebraVault/Sources/ZebraVault/Email/ZebraClawvisorEmailClient.swift,
2026-06-09; Source:
Packages/ZebraVault/Sources/ZebraVault/AgentOnboarding/ZebraOnboardingChecklist.swift,
2026-06-09]

여기서 중요한 것은 완료 판정이 terminal source를 보면 안 된다는 점이다.

- 사용자가 sidebar Gmail Connect에서 연결을 끝내면 checklist `.email`이 완료되어야
  한다.
- 사용자가 checklist Email Start에서 연결을 끝내면 sidebar email mode가 connected
  상태로 전환되어야 한다.
- 완료 상태의 source of truth는 `emailListStore.isConnected`와 `~/.gbrain/.env`의
  Clawvisor Gmail 설정이다.
- `ZebraOnboardingChecklistStepID.email`이나 agent terminal registry source는 완료
  판정에 쓰지 않는다.

현재 checklist store는 주기적으로 외부 상태를 sync하므로 기능상 맞는 방향에 있지만,
구현 시에는 `~/.gbrain/.env` 또는 그 부모 디렉터리도 completion watcher 대상에 넣어
완료 반영을 30초 polling에만 맡기지 않게 한다.

### Flow별 setup packet

두 번째 작업은 Claude Code 전용 prompt를 flow별 setup packet으로 일반화하는 것이다.
기존 sidebar agent picker는 Claude Code만 활성화하는 모델이었고,
`ZebraSourceOnboardingGmailCommand`도 Claude Code의 `/clawvisor-setup` 절차를 전제로
했다. 이제는 `flowKind`에 따라 packet content를 나눈다. [Source:
Packages/ZebraVault/Sources/ZebraVault/Email/ZebraSourceOnboardingGmailCommand.swift,
2026-06-09; Source: Clawvisor Generic Agent Integration Guide,
https://raw.githubusercontent.com/clawvisor/clawvisor/main/docs/INTEGRATE_GENERIC.md,
2026-06-09]

Claude Code flow는 현재 7단계 구조를 보존한다. Codex와 Antigravity generic flow는
Clawvisor generic-agent guide 기준으로 `CLAWVISOR_URL`, agent token, catalog verify,
standing Gmail task, `~/.gbrain/.env` 작성으로 간다. OpenClaw flow는 Clawvisor
OpenClaw integration guide 기준으로 OpenClaw에 Clawvisor skill/webhook/env를 설치하고,
마지막에는 Zebra가 읽는 `~/.gbrain/.env` 네 key를 남기는 것으로 끝낸다. [Source:
Clawvisor OpenClaw Integration Guide,
https://raw.githubusercontent.com/clawvisor/clawvisor/main/docs/INTEGRATE_OPENCLAW.md,
2026-06-09]

Codex와 Antigravity launch 자체는 새로 발명하지 않는다. Zebra의 ChatPill
경로에는 이미 Codex를 `codex -C ...` 형태로 시작하고, Antigravity를
`agy --prompt-interactive --add-dir ...` 형태로 시작하는 contract가 있다.
이 convention을 재사용해야 prompt가 유실되지 않고, agent별 CLI 차이도 한곳에서
관리된다. [Source: local `codex --help`, 2026-06-02; Source: local
`agy --help`, 2026-06-02; Source:
Packages/ZebraVault/Sources/ZebraVault/MarkdownChatPill/MarkdownChatPillCommand.swift,
2026-06-02]

## 실행 순서

### 1. Email launch 동작 고정

먼저 `.email` checklist step이 `openZebraAgentTerminal`을 통해 agent terminal로
열리는 동작을 테스트로 고정한다. 이건 이미 main에 들어온 terminal placement 변경의
회귀 방지다. source는 checklist entrypoint를 나타내는 `.onboardingChecklist(.email)`로
유지하되, 이 terminal이 agent panel/companion panel 정책의 대상이라는 점을 보장한다.

확인할 동작은 작게 잡는다.

- checklist Email Start가 agent terminal을 연다.
- 해당 terminal은 companion placement 정책의 대상이 된다.
- terminal registry source는 `.onboardingChecklist(.email)`로 남는다.
- registry에는 선택된 agent metadata가 남는다.

### 2. Shared command builder 추가

Sidebar Connect와 checklist Email Start가 공유할 Clawvisor email onboarding command
builder를 만든다. 이 builder는 primary agent 해석, prompt, cwd, env write target만
다룬다. sidebar와 checklist는 같은 builder 결과를 받아가지만, sidebar는
`.onboardingChecklist(.sourceOnboarding)`, checklist는 `.onboardingChecklist(.email)` source로 terminal을
연다.

호출자는 자기 UI 상태만 책임진다. checklist는 row running state를 관리하고, sidebar는
email mode의 repair/connect 상태를 관리한다. prompt나 agent CLI invocation은 두
entrypoint가 따로 만들지 않는다.

### 3. Setup packet/state scaffolding 추가

GBrain setup처럼 이메일 전용 state file, setup packet, helper command를 먼저 만든다.
여기서 중요한 것은 setup state가 completion receipt를 대체하지 않는다는 점이다.
setup state는 다음 launch에서 어느 section부터 이어갈지, 어떤 flowKind를 써야
하는지, waiting reason이 무엇인지를 기록하는 용도다. secret은 저장하지 않는다.

### 4. FlowKind resolver 추가

launch 시점에 primary agent와 GBrain runtime receipt를 읽어 `flowKind`를 결정한다.
`runtime == openclaw`이면 OpenClaw flow로 고정하고, 그렇지 않으면 primary agent가
Claude인지 여부로 Claude Code/generic agent flow를 나눈다. primary agent가 없거나
준비되지 않았으면 이메일 onboarding이 installer를 복제하지 않고 agent onboarding
step으로 돌려보낸다.

### 5. Flow별 packet content 추가

Claude Code flow는 현재 7단계 구조를 유지한다. generic agent flow는 Codex와
Antigravity가 공통으로 쓰고, OpenClaw flow는 Clawvisor OpenClaw guide를 packet
안에 녹여서 primary agent가 그대로 읽고 진행하게 한다. 즉 "누가 대화하느냐"와
"무엇을 설치 target으로 삼느냐"를 분리한다.

### 6. 완료 감지 즉시성 보강

사이드바에서 연결을 끝낸 경우에는 `~/.gbrain/.env` 네 key와 repair state 해제로
checklist `.email`이 완료되어야 한다. 체크리스트에서 연결을 끝낸 경우에는 sidebar가
같은 설정을 읽고 refresh를 거쳐 connected/inbox 상태로 전환되어야 한다.

이를 위해 checklist completion watcher가 `~/.gbrain/.env` 변경을 즉시 감지하게 한다.
30초 polling은 fallback으로 남길 수 있지만, 사용자 눈에는 연결 완료 직후 checklist가
체크되는 것이 맞다.

### 7. 재연결/복구 상태 문구 분리

재연결/복구 상태를 Gmail 재연결, Clawvisor task 재승인, local agent/config 복구로
나눠 UI 문구와 agent prompt에 반영한다. 모든 실패를 "Gmail 다시 연결"로 부르면
사용자가 실제로 해야 할 일이 흐려진다.

## 완료 판정 계약

### Source of truth

체크리스트 이메일 step은 "이 버튼에서 시작한 terminal이 성공했는가"를 보지 않는다.
완료 여부는 Zebra가 실제로 Gmail을 읽고 쓸 수 있는 준비 상태인지로만 판단한다.
현재 코드 기준으로는 `~/.gbrain/.env`에 `CLAWVISOR_URL`,
`CLAWVISOR_AGENT_TOKEN`, `CLAWVISOR_GMAIL_TASK_ID`,
`ZEBRA_CLAWVISOR_GMAIL_ACCOUNT`가 모두 있고, `emailConnectionRepairState == nil`
일 때 `.email`이 완료된다. `isConnected`는 사용자에게 보이는 현재 inbox 상태를
설명하는 signal이지, setup packet/state의 대체물이 아니다. 구현 시 이 방향을
명시적으로 유지한다. [Source:
Packages/ZebraVault/Sources/ZebraVault/Email/ZebraClawvisorEmailClient.swift,
2026-06-09; Source:
Packages/ZebraVault/Sources/ZebraVault/AgentOnboarding/ZebraOnboardingChecklist.swift,
2026-06-09]

### Entry point별 결과

이 계약 때문에 sidebar Gmail Connect와 checklist Email Start는 서로를 대체하거나
경쟁하지 않는다. 사용자가 sidebar에서 먼저 연결을 끝내면 checklist row가 완료되고,
사용자가 checklist에서 먼저 연결을 끝내면 sidebar email mode가 connected 상태를
읽는다. 체크리스트의 `stepID`는 row 식별자이고, agent terminal registry의 source는
terminal 분류다. 둘 중 어느 것도 연결 완료의 source of truth가 아니다. [Source:
Packages/ZebraVault/Sources/ZebraVault/AgentOnboarding/ZebraOnboardingChecklist.swift,
2026-06-02; Source: Sources/Zebra/Sidebar/ZebraSidebarBody.swift, 2026-06-02]

## 재연결/복구 상태 분류

### Gmail 재연결

재연결이 필요한 상황은 한 종류가 아니다. Google/Gmail 쪽 재연결은 사용자가
Google 계정에서 app access를 revoke했거나, refresh token이 invalid/expired 되었거나,
Workspace admin policy가 막았거나, OAuth app testing mode의 token 수명 제한을
맞았을 때 발생한다. 이때는 실제로 Gmail 권한을 다시 승인해야 한다. [Source:
Google OAuth 2.0 documentation,
https://developers.google.com/identity/protocols/oauth2, 2026-06-02; Source:
Google OAuth 2.0 best practices,
https://developers.google.com/identity/protocols/oauth2/resources/best-practices,
2026-06-02]

### Clawvisor task 재승인

Clawvisor task 복구는 Gmail 계정 자체보다 Zebra가 쓰는 standing Gmail task가
문제인 경우다. `CLAWVISOR_GMAIL_TASK_ID`가 없거나, task가 expired/revoked/denied
상태거나, task를 찾을 수 없거나, `send_message` 같은 action scope가 추가되어
재승인이 필요할 때 여기에 해당한다. 이 경우 UI와 prompt는 "Gmail 다시 연결"보다
"Clawvisor 승인 다시 하기" 또는 "Gmail task 다시 승인"에 가까워야 한다. [Source:
Packages/ZebraVault/Sources/ZebraVault/Email/ZebraClawvisorEmailClient.swift,
2026-06-02]

### Local agent/config 복구

local agent/config 복구는 `~/.gbrain/.env`가 삭제되었거나 key가 누락되었거나,
`CLAWVISOR_AGENT_TOKEN`이 더 이상 유효하지 않거나, primary agent preference는
있지만 해당 CLI/auth가 준비되지 않은 경우다. 이 경우 이메일 onboarding이
`zebra-agent-onboarding`을 직접 실행해 설치 UX를 복제하지 않는다. agent 설정이
깨졌다는 사실을 알려주고 agent onboarding/scan 단계로 돌려보낸다.

## Standing Gmail task 계약

### Env contract

agent-guided flow는 항상 standing Gmail task를 만들거나 찾고,
`~/.gbrain/.env`에 아래 네 값을 남기는 것으로 끝나야 한다.

```env
CLAWVISOR_URL=<Clawvisor URL>
CLAWVISOR_AGENT_TOKEN=<agent token>
CLAWVISOR_GMAIL_TASK_ID=<standing Gmail task id>
ZEBRA_CLAWVISOR_GMAIL_ACCOUNT=<Gmail account>
```

### Required actions

standing task에는 `list_messages`, `get_message`, `get_thread`,
`get_attachment`, `create_draft`, `send_message`, `archive_message`가 필요하다.
각 action은 `auto_execute: true`여야 한다. Zebra가 사용자에게 보이는 승인
표면이고, 특히 `send_message`는 사용자가 Zebra UI에서 명시적으로 Send를 누른
뒤에만 호출되기 때문이다. [Source:
Packages/ZebraVault/Sources/ZebraVault/Email/ZebraClawvisorEmailClient.swift,
2026-06-02; Source:
Packages/ZebraVault/Sources/ZebraVault/Email/ZebraSourceOnboardingGmailCommand.swift,
2026-06-02]

## 검증

### Unit tests

검증은 네 겹으로 나눈다.

- launch test: `.email` checklist launch가 `openZebraAgentTerminal` placement를
  유지하고, `.onboardingChecklist(.email)` source와 agent metadata를 함께 남기는지
  확인한다. sidebar launch는 `.onboardingChecklist(.sourceOnboarding)` source를 유지하는지 본다.
- resolver test: `primaryAgent x selectedRuntime` 조합에서 `flowKind`가 의도한 대로
  결정되는지 확인한다. 특히 `runtime == openclaw`이면 primary agent와 무관하게
  OpenClaw flow를 선택하고, `runtime == hermes`이면 primary agent 기준의
  Claude/generic flow로 가는지 본다.
- packet/state test: setup packet 파일 권한이 0600인지, state가
  `completedSections/nextSection/waitingForUser`를 저장하는지, 다음 launch에서 재개
  컨텍스트가 복원되는지 확인한다.
- completion test: checklist store가 `~/.gbrain/.env` 네 key와 repair state를 기준으로
  이메일 단계를 완료 처리하는지 확인한다. sidebar에서 연결 완료를 시뮬레이션했을 때도
  checklist `.email`이 완료되는 케이스를 둔다.

### Manual check

로컬 수동 확인은 tagged Debug reload로 한다. 체크리스트 Email Start를 누르면 agent
terminal이 기존 companion placement 정책대로 열려야 하고, agent가 `~/.gbrain/.env`를
쓰면 sidebar가 disconnected 상태에서 inbox로 전환되어야 한다. [Source: AGENTS.md,
2026-06-02]

## 리서치 caveat

Offlight GBrain thin-client routing을 먼저 확인했지만, 2026-06-02 기준 Railway
host에서 OAuth discovery 404가 나서 `doctor`와 `get`이 실패했다. 그래서 이
플랜은 local brain file, repository inspection, local CLI help, 공개 Clawvisor
guide를 기준으로 작성했다. [Source: local GBrain CLI output, 2026-06-02]
