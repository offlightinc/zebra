# 에이전트 온보딩 단일 터미널 전환 계획

작성일: 2026-06-12

## 목표

에이전트 온보딩에서 Step 1 에이전트 터미널이 실제로 사용 가능한 상태가 되기 전에 Step 2 터미널을 따로 열면 안 된다. Claude와 Codex는 Step 1에서 열린 터미널이 그대로 실제 Step 2 에이전트 작업을 수행하는 터미널이 되어야 한다.

기대 동작:

- 선택된 primary agent가 이미 설치되어 있고 인증도 완료되어 있으면, Step 1 터미널에서 바로 Step 2 에이전트 명령을 실행한다.
- 선택된 primary agent가 설치되어 있지만 인증이 안 되어 있으면, 같은 터미널에서 provider 계정 연동, trust, first-run prompt를 처리하고, provider CLI가 지원한다면 그대로 Step 2 에이전트 작업으로 이어진다.
- 선택된 primary agent가 설치되어 있지 않으면, Zebra는 기존처럼 설치 flow를 먼저 실행할 수 있다. 다만 설치 후 rescan이 끝나면 새 터미널을 열지 않고, 현재 온보딩 터미널에서 같은 Step 2 에이전트 명령을 실행한다.

## 현재 코드 구조

현재 flow는 두 개의 독립적인 launch path로 나뉘어 있다.

1. Step 1 터미널 launch:
   - `Sources/Zebra/Sidebar/ZebraSidebarBody.swift`
   - `startOnboardingChecklistStep(.agent)`가 `ZebraOnboardingChecklistCommand.shellStartupLine(for: .agent, ...)`에서 startup line을 받는다.
   - 이 startup line은 `Resources/zebra-agent-onboarding`을 실행한다.

2. Step 1 shell script:
   - `Resources/zebra-agent-onboarding`
   - `launch_selected_agent()`가 background `readiness_poll_loop`를 시작한다.
   - 그 다음 bare Claude/Codex를 대략 아래 형태로 실행한다.
     `cd "$ONBOARDING_CWD" && "$executable_path"`
   - background readiness watcher는 interactive 에이전트 프로세스가 아직 살아 있는 동안에도 onboarding complete를 기록할 수 있다.

3. Step 2 자동 launch:
   - `Sources/Zebra/Sidebar/ZebraSidebarBody.swift`
   - `handleOnboardingCompletionChange()`가 `.agent` 완료를 감지한다.
   - `pendingGBrainRuntimeStartAfterAgentLaunch == true`이면 `startOnboardingChecklistStep(.gbrainRuntime)`를 호출한다.
   - 이 호출이 Step 2용 새 터미널을 연다.

4. Step 2 명령 생성:
   - `Packages/ZebraVault/Sources/ZebraVault/AgentOnboarding/ZebraOnboardingChecklist.swift`
   - `.gbrainRuntime`은 `ZebraGBrainRuntimeOnboardingStore().prepareLaunch()`를 호출한다.
   - `gbrainRuntimeStartupLine(...)`이 실제 Claude/Codex/Antigravity Step 2 에이전트 invocation을 만든다.
   - Claude의 경우 `MarkdownChatPillCommand.shellStartupLineForGBrainSetup(...)`이 저장된 `primaryAgentExecutablePath`를 사용할 수 있다.

## 중요한 제약

bare Claude/Codex를 먼저 실행한 뒤, readiness가 통과하면 parent shell에서 Step 2를 이어 실행하는 방식으로 해결하면 안 된다.

이유: shell script가 bare `claude` 또는 bare `codex`를 실행하면 parent shell은 그 프로세스가 종료될 때까지 막힌다. 에이전트가 interactive prompt에 진입해서 살아 있으면, parent shell은 같은 터미널에서 Step 2 명령을 실행할 수 없다. background watcher는 state를 쓸 수는 있지만, 이미 실행 중인 에이전트 프로세스를 다른 Step 2 invocation으로 바꿀 수는 없다.

그래서 이 방식은 결국 둘 중 하나가 된다.

- 사용자가 에이전트 프로세스를 종료할 때까지 기다린다. 이건 원하는 flow가 아니다.
- 살아 있는 PTY/에이전트 프로세스에 input automation을 한다. 이건 취약하므로 첫 설계로 두면 안 된다.

## 제안 방향

체크리스트에서 시작하는 agent onboarding은 Step 1 마지막에 bare agent를 launch하지 말고, 선택된 primary agent의 실제 Step 2 명령을 실행하도록 바꾼다.

즉 Step 1은 scan/select/install을 계속 담당하되, Claude primary agent가 선택된 뒤에는 아래처럼 실행한다.

```text
cd <gbrain-runtime-work>
<selected claude executable> --permission-mode auto --append-system-prompt <context> <step2 prompt>
```

기존처럼 아래를 실행하지 않는다.

```text
cd <onboarding cwd>
<selected claude executable>
```

이렇게 하면 auth/login/trust 처리와 Step 2 에이전트 작업이 하나의 Claude 프로세스, 하나의 터미널 안에 묶인다.

Codex도 같은 원칙을 따른다. Codex는 `MarkdownChatPillCommand.shellStartupLineForGBrainSetup(...)`이 현재 만드는 Step 2 Codex invocation을 그대로 사용해야 한다. 이 명령에는 기존 sandbox, approval, project trust 옵션이 포함된다. Step 1에서 bare `codex`를 실행한 뒤 sidebar가 Step 2 새 터미널을 열게 두면 안 된다.

## 구체적인 구현 계획

### 1. checklist Step 1에만 chained Step 2 launch mode 추가

`ZebraOnboardingChecklistCommand.shellStartupLine(for: .agent, ...)`를 바꿔서, checklist 전용 Step 1 launch가 Step 2 command template 경로를 함께 넘길 수 있게 한다.

모든 `ZebraAgentOnboardingScriptCommand` caller를 전역으로 바꾸면 안 된다. 다른 surface가 단순히 primary agent 선택만 원할 수 있으므로, 기존 동작은 유지해야 한다.

### 2. Step 1을 launch하기 전에 Step 2 command 생성

Swift에서 `.agent` checklist startup line을 만들 때:

- `ZebraGBrainRuntimeOnboardingStore().prepareLaunch()`를 준비한다.
- 현재 `.gbrainRuntime`이 쓰는 helper path, instruction document, prompt를 사용해서 Step 2 startup line을 만든다.
- 그 Step 2 command를 Application Support 아래 파일에 쓴다. 예:

```text
~/Library/Application Support/zebra/onboarding/chained-step2-command.sh
```

이 파일에 아직 확정되지 않은 Claude/Codex executable path를 너무 일찍 박으면 안 된다. 가능한 방식은 두 가지다.

- placeholder token을 써두고, shell script가 정확한 executable path를 선택한 뒤 치환한다.
- Step 1이 `primaryAgentExecutablePath`를 저장한 뒤, Step 2 command가 그 값을 읽게 한다.

더 안전한 쪽은 Step 1 script가 마지막 순간에 선택된 executable path를 주입하는 방식이다.

### 3. `zebra-agent-onboarding`에 명시적 옵션 추가

예를 들어 아래 옵션을 추가한다.

```bash
--continue-with-command-file <path>
```

이 옵션의 의미:

- primary agent 선택/설치가 성공한 뒤,
- foreground main script process에서만,
- bare Claude/Codex를 launch하지 않고 해당 파일의 command를 실행한다.

이 옵션은 background readiness watcher에서 실행되면 안 된다.

### 4. 선택된 agent launch 지점에서 Step 2 command 실행

`launch_selected_agent()` 안에서:

- `agent`가 chained Step 2 launch를 지원하는 agent이면, 우선 Claude와 Codex부터 시작한다.
- `--continue-with-command-file`이 있고,
- command file이 존재하면,

아래 순서로 처리한다.

1. launch 전에 `primaryAgent`와 `primaryAgentExecutablePath`를 저장한다.
2. `agent_launch_chained_step2_started` 같은 event를 기록한다.
3. 현재 터미널에서 Step 2 command를 실행한다.
4. 기존 `readiness_poll_loop`는 시작하지 않는다. 이 watcher가 Step 1 complete를 너무 일찍 기록하고 UI의 Step 2 새 터미널 launch를 유발할 수 있기 때문이다.

명령은 가능하면 선택된 absolute executable path를 사용해야 한다. plain `claude`나 plain `codex`에 의존하면 안 된다.

### 5. chained Step 1에서는 UI 자동 Step 2 launch 비활성화

`Sources/Zebra/Sidebar/ZebraSidebarBody.swift`에서 Step 1 launch가 chained mode일 때는 `pendingGBrainRuntimeStartAfterAgentLaunch`를 `true`로 세팅하지 않는다.

이렇게 해야 아래 race를 막을 수 있다.

```text
agent completion -> handleOnboardingCompletionChange -> open Step 2 terminal
```

chained mode에서는 Step 2가 이미 같은 터미널에서 실행 중이어야 하므로, UI가 별도 Step 2 터미널을 열면 안 된다.

### 6. 완료 의미 정리

현재 `.agent` 완료는 "primary agent가 선택됐고 usable하다"에 가깝다. 하지만 chained flow에서는 이 완료만으로 새 터미널을 시작하면 안 된다. Step 2는 이미 같은 터미널에서 실행 중이기 때문이다.

Step 2 완료 여부는 기존처럼 Step 2 helper가 `gbrain-runtime-state.json`을 쓰는 것으로 판단한다.

## 구현 전 필수 확인

최종 구현 전에 로그아웃 또는 fresh Claude 환경에서 아래를 확인해야 한다.

```bash
<absolute claude path> --permission-mode auto --append-system-prompt '<small system prompt>' 'Reply exactly: ok'
```

Claude가 로그아웃 상태일 때 무엇이 일어나는지 확인한다.

1. Claude가 login/trust flow를 시작한 뒤, 로그인 완료 후 원래 prompt를 계속 수행하는가?
2. 아니면 not-logged-in error로 즉시 종료되는가?

즉시 종료된다면 단일 터미널 설계에는 wrapper loop가 필요하다.

```text
Step 2 Claude command 실행
auth-required로 실패하면:
  interactive Claude auth 실행
  auth process가 끝난 뒤 Step 2 Claude command 재실행
```

이 fallback은 덜 이상적이다. 사용자가 interactive auth Claude 프로세스를 종료해야 Step 2가 시작될 수 있기 때문이다. 따라서 먼저 증명해야 하는 것은 실제 Step 2 Claude invocation이 Claude login flow 이후 원래 prompt로 자연스럽게 이어지는지 여부다.

Codex도 같은 방식으로 확인해야 한다.

```bash
<absolute codex path> -C <gbrain-runtime-work> --sandbox workspace-write --ask-for-approval on-request '<small prompt>'
```

Codex가 로그인 flow 이후 원래 prompt를 이어서 처리하지 않고 auth-required 상태로 종료한다면, Codex에도 같은 auth-then-command wrapper 판단이 필요하다. 설계는 agent 공통이어야 하고, provider별 차이는 command construction과 auth-required 감지에만 둔다.

## 리스크

- Claude가 로그인 후 원래 prompt를 이어서 처리하지 않으면, fallback loop가 필요하고 완전히 매끄러운 단일 flow가 아닐 수 있다.
- Step 2 command 생성 시점이 선택된 executable path 확정 전이면, 잘못된 Claude/Codex binary가 command에 박힐 수 있다.
- 기존 UI auto-start가 남아 있으면 Zebra가 여전히 두 번째 Step 2 터미널을 열 수 있다.
- chained mode에서 기존 background readiness watcher가 살아 있으면 Step 1을 너무 빨리 complete 처리할 수 있다.

## 하지 않을 것

- `974abfc4f`의 shell rc 수정 방식은 되살리지 않는다.
- `.zshrc`, `.zprofile`, `.bashrc`, fish config를 자동 수정하지 않는다.
- global PATH 순서를 바꾸는 방식으로 해결하지 않는다.
- 이 조사/설계 때문에 새 build tag를 추가하지 않는다.

## 다음 단계 제안

아직 구현하지 않는다. 먼저 로그아웃 상태에서 Claude/Codex command-continuation probe를 실행하고 실제 동작을 확인한다. 그 결과에 따라 둘 중 하나를 선택한다.

1. provider CLI가 로그인 후 원래 command를 이어서 실행하면, direct single-command Step 2 launch로 간다.
2. provider CLI가 auth-required로 종료하면, explicit auth-then-command wrapper로 간다.

