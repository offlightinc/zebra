# Zebra GBrain Runtime Agent Onboarding

이 문서는 Zebra 온보딩 Step 2의 기준 문서다.

Step 2는 이후 GBrain setup을 받쳐 줄 OpenClaw 또는 Hermes runtime layer를
준비한다. 이 단계는 agent-orchestrated flow다. Step 1에서 선택된 primary
agent가 이 문서를 읽고, Zebra helper/report command를 호출하고, 진행 상태를
기록한다. helper는 deterministic check, install, verification, state write만
담당한다.

Step 2는 GBrain source repo를 준비하지 않는다. Source repo 선택, clone/reuse,
docs snapshot, `bun install`, `bun install -g .` 또는 `bun link`, 그리고
`gbrain --version` 검증은 Step 3 책임으로 남긴다.

## 단계 경계

### Step 1: primary agent bootstrap

Step 1은 Codex, Claude, Antigravity 중 하나를 global CLI로 실행 가능하게 만든다.
아직 primary agent가 없으므로 Step 1은 deterministic shell-script flow가 맞다.

Step 1이 끝나면 Zebra는 선택된 primary agent를 새 terminal에서 시작한다.

### Step 2: runtime/prerequisite setup

Step 2는 primary agent가 진행한다.

Agent는 반드시 다음을 지킨다:

- 이 문서를 읽는다.
- `zebra-gbrain-runtime-onboarding` command를 호출한다.
- workflow section 전후로 `report`를 호출한다.
- 제품 선택 또는 blocking OS prompt가 필요한 경우에만 사용자에게 묻는다.
- 이 contract 밖의 install command를 임의로 만들지 않는다.

Helper는 다음을 담당한다:

- prerequisite fact를 감지한다.
- 승인된 recovery/install command를 실행한다.
- 선택된 runtime을 configure한다.
- 선택된 runtime이 LLM을 호출할 수 있는지 verify한다.
- state와 final receipt를 쓴다.

Helper는 runtime/provider 선택을 사용자에게 직접 묻고 setup 전체를 끝까지 진행하는
end-to-end interactive flow를 실행하면 안 된다.

### Step 3: GBrain setup

Step 3는 기존 repo-first GBrain flow를 유지한다.

Step 3는 `activeGBrainBinding.sourceRepoPath`를 준비하고, `~/gbrain` 또는
사용자가 선택한 source repo를 clone/reuse하고, local GBrain docs를 snapshot하고,
repo-local `bun install`을 실행하고, active repo를 user-visible `gbrain` command로
노출한 뒤 `gbrain --version`을 검증한다.

## 문서 모델

Step 2는 이 고정 Zebra-owned 문서를 authoritative workflow document로 사용한다.

Step 2용 run-specific prompt artifact는 만들지 않는다. Step 3는 active GBrain source
docs와 snapshot commit이 실행마다 달라질 수 있어서 section prompt를 실행마다 생성한다.
Step 2에는 그런 외부 문서 snapshot 문제가 없다.

현재 실행 context는 helper에서 가져온다:

```bash
zebra-gbrain-runtime-onboarding run
zebra-gbrain-runtime-onboarding status --json
zebra-gbrain-runtime-onboarding preflight --json
```

`run`은 non-interactive wrapper다. 현재 status, next action, 이 문서 경로를 출력할
수는 있지만, 질문을 하거나 full setup flow를 직접 수행하면 안 된다.

## Helper Command

Step 2 helper는 `zebra-gbrain-runtime-onboarding`이다.

작고 deterministic한 command를 제공해야 한다:

```bash
zebra-gbrain-runtime-onboarding run
zebra-gbrain-runtime-onboarding status --json
zebra-gbrain-runtime-onboarding preflight --json
zebra-gbrain-runtime-onboarding report --status <status> --section <section> [--note <note>]
zebra-gbrain-runtime-onboarding recover-prerequisite <clt|node|bun>
zebra-gbrain-runtime-onboarding install-runtime <openclaw|hermes>
zebra-gbrain-runtime-onboarding configure-runtime <openclaw|hermes> ...
zebra-gbrain-runtime-onboarding interactive-auth <openclaw|hermes> --provider <provider-id>
zebra-gbrain-runtime-onboarding verify-runtime <openclaw|hermes>
zebra-gbrain-runtime-onboarding write-receipt
```

허용되는 report status:

```text
started
completed
waiting_for_user
failed
```

Agent는 다음과 같은 형태로 report를 사용한다:

```bash
zebra-gbrain-runtime-onboarding report --status started --section "Baseline preflight"
zebra-gbrain-runtime-onboarding preflight --json
zebra-gbrain-runtime-onboarding report --status completed --section "Baseline preflight"
```

## Workflow

### 1. Baseline preflight

가장 먼저 preflight를 실행한다. Preflight는 넓게 감지하되 아무것도 설치하지 않는다.
Command Line Tools 또는 `python3`가 없더라도 preflight/status 단계에서는
`xcode-select --install`을 실행하지 않는다.

Preflight fact에는 다음을 포함한다:

- `python3`
- `/bin/sh`
- `/bin/bash`
- `curl`
- `git`
- `xcode-select` / Command Line Tools 상태
- `node`
- `npm`
- `bun`
- `openclaw`
- `hermes`

각 fact는 다음을 기록한다:

- `detectedAt`
- `ok`
- `path`
- `version`
- `requiredFor`
- `blockingNow`
- `reason`

특정 경로에서만 필요한 tool이 없다고 해서 즉시 blocker로 만들지 않는다. 예를 들어
`npm`이 없어도 사용자가 OpenClaw를 선택하기 전에는 blocking이 아니다.

### 2. Choose runtime

Agent가 preflight 결과를 보고 user-facing runtime branch를 선택하게 한다. Helper가
이 질문을 직접 하면 안 된다.

유효한 runtime 선택지:

```text
openclaw
hermes
```

Agent는 현재 상태에 맞는 선택지만 설명한다:

- OpenClaw만 설치됨: OpenClaw 사용, 또는 Hermes 설치 후 사용.
- Hermes만 설치됨: Hermes 사용, 또는 OpenClaw 설치 후 사용.
- 둘 다 설치됨: 사용할 runtime 선택.
- 둘 다 없음: Zebra가 설치할 runtime 선택.

Agent는 선택되지 않은 runtime의 dependency를 설치하지 않는다.

### 3. Recover common prerequisites

선택된 runtime과 무관하게 Step 3에서 필요한 prerequisite만 복구한다:

- Command Line Tools / `git`
- `bun`

Python은 설치하지 않는다.

Command Line Tools가 없으면 먼저 사용자에게 다음 내용을 설명한다:

```text
이제 macOS Command Line Tools가 필요합니다.
설치 창이 열리면 설치를 눌러주세요.
```

그 다음에만 다음을 trigger한다:

```bash
xcode-select --install
```

이 작업은 recoverable이지만 blocking이다. 사용자가 macOS installer UI를 완료해야
하기 때문이다. `blockingReason: clt_install_required`를 기록한다. 이 명령은
`recover-prerequisite clt`에서만 실행한다.

`bun`이 없으면 official Bun installer를 사용한다:

```bash
curl -fsSL https://bun.sh/install | bash
```

`~/.bun/bin/bun --version`을 검증한다. 새 shell에서 `bun`이 PATH로 resolve되는지도
기록한다.

### 4. Recover selected-runtime prerequisites

선택된 runtime에 필요한 prerequisite만 복구한다.

#### OpenClaw

OpenClaw는 Node/npm이 필요하다.

`node` 또는 `npm`이 없으면 official Node.js macOS pkg install path를 사용한다.
Homebrew를 설치하지 않는다. Zebra-private Node/npm runtime을 만들지 않는다.

Node 설치 후 일반 terminal PATH에서 다음이 resolve되는지 검증한다:

```bash
node --version
npm --version
```

`openclaw`가 없으면 다음으로 설치한다:

```bash
npm install -g openclaw
```

설치 전에 `npm config get prefix`로 현재 npm global prefix를 확인한다. 현재 prefix가
global package install에 필요한 `bin`과 `lib/node_modules`를 쓸 수 있으면 그대로 둔다.
root-owned `/usr/local`처럼 현재 사용자가 쓸 수 없는 prefix면 다음을 먼저 실행한다:

```bash
mkdir -p "$HOME/.local/bin" "$HOME/.local/lib/node_modules"
npm config set prefix "$HOME/.local"
```

그 뒤 같은 `npm install -g openclaw`를 실행한다. 이 설정은 Zebra-private runtime이
아니라 사용자 계정의 npm global prefix를 고치는 것이다. 이후 `~/.local/bin`이 PATH에
있으면 `openclaw`와 future npm global command가 일반 terminal에서도 resolve된다.

#### Hermes

Hermes는 이 onboarding path에서 Node/npm을 요구하지 않는다.

`hermes`가 없으면 현재 검증된 minimal installer command를 그대로 사용한다:

```bash
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- --skip-setup --skip-browser --no-skills --non-interactive
```

Hermes detect 후보:

- `command -v hermes`
- `$HERMES_INSTALL_DIR/venv/bin/hermes`
- `~/.local/bin/hermes`
- `~/.hermes/hermes-agent/venv/bin/hermes`
- `/usr/local/bin/hermes`

Python/venv installer failure는 exit code, stderr tail, blocking reason과 함께 기록한다.

### 5. Configure selected runtime

선택된 runtime만 configure한다.

필요하면 agent가 사용자에게 LLM connection/provider 선택을 묻는다. Helper는 구체적인
runtime configuration command를 실행하고 non-secret state를 쓴다.

Provider 선택을 물을 때는 bullet list를 쓰지 말고 번호 선택지로 제시한다. 사용자는
provider id가 아니라 번호로 답할 수 있어야 한다. 예:

```text
사용할 계정/키 방식을 선택해주세요.

1. ChatGPT/Codex 계정으로 로그인
2. Claude Code 계정으로 로그인
3. OpenRouter API key 사용
4. Anthropic API key 사용
5. Google Gemini API key 사용
6. OpenAI API key 사용
```

Hermes runtime에서만 2번 선택지 label을 다음처럼 바꾼다:

```text
2. Claude Code 계정으로 로그인 (Claude Max plan + extra usage credits 필수)
```

사용자가 OpenClaw + Claude Code를 선택하면 agent는 다음 command를 그대로 호출한다:

```bash
zebra-gbrain-runtime-onboarding configure-runtime openclaw --provider anthropic-claude-code
```

그 외 선택지는 해당 provider id로 `configure-runtime <runtime> --provider
<provider-id>`를 호출한다.

Secret 값은 Zebra state에 쓰면 안 된다. State에는 environment variable 이름,
OAuth source, entered-key source label 같은 key source만 기록할 수 있다.

OpenClaw/Hermes OAuth 또는 provider CLI login이 실제 terminal TTY를 요구하면,
agent tool 안에서 login command를 계속 실행하지 않는다. Helper는
`interactive_auth_required`를 state에 쓰고, 실제 Zebra terminal에서 실행할
`interactive-auth` command를 `interactiveAuth.command`에 기록한다.
Zebra 앱은 이 pending state를 watch해서 실제 terminal을 연다. 앱은 state의 raw
command string을 그대로 실행하지 않고, `runtime`, `provider`, `requestedAt` 같은
구조화된 request 값을 검증한 뒤 Zebra-owned helper command를 조립해서 실행한다.
같은 request는 자동으로 한 번만 실행하고, 같은 runtime/provider의 반복 request는 짧은
간격 안에서 다시 열지 않는다. Auth command가 성공하면 terminal은 자동 종료되고,
실패하거나 취소되면 사용자가 원인을 확인할 수 있도록 terminal을 남긴다.

OpenClaw + Claude Code에서 `openclaw_claude_cli_registration_requires_tty`가 나오면,
Claude Code 계정 로그인이 필요한 상태가 아니다. Claude CLI 로그인은 이미 확인됐고,
OpenClaw가 그 로그인을 재사용하도록 등록하는 단계다. 이때는 다음처럼 안내한다:

```text
OpenClaw가 Claude CLI 로그인을 재사용하도록 등록합니다.

새 터미널이 열려 자동 등록을 진행하고, 성공하면 자동으로 닫힙니다.
터미널이 닫히면 여기로 돌아와 완료됐다고 알려주세요.
```

Agent는 이 상태를 실패로 처리하지 않는다. 사용자가 real terminal에서
`interactive-auth`를 완료한 뒤에는 `configure-runtime`을 다시 호출하지 않는다.
먼저 `status --json`을 호출하고, `runtimeConfig.result.ok == true`이면 바로
`verify-runtime <runtime>`으로 넘어간다. `runtimeVerification.result.ok == true`이면
`write-receipt`를 호출한다.

### 6. Verify selected runtime

선택된 runtime이 minimal LLM call을 할 수 있는지 verify한다.

OpenClaw는 model/auth status probe path를 사용한다.

Hermes는 helper에서 이미 사용하는 minimal chat/status path를 사용한다.

Verification 결과는 `llmCall` check로 기록한다.

### 7. Write runtime receipt

선택된 runtime이 설치, configure, verify까지 끝나면 final receipt를 다음 파일에 쓴다:

```text
~/Library/Application Support/zebra/onboarding/gbrain-runtime-state.json
```

Checklist는 receipt가 complete이고 required check가 모두 true일 때만 Step 2를 완료로
봐야 한다.

## Prerequisite Policy

### python3

Python은 설치하지 않는다.

가능하면 system/CLT 제공 `python3`를 사용한다. 없으면 `python3_missing` 같은 blocking
state를 기록한다. Python installer를 실행하지 않는다.

### /bin/sh and /bin/bash

이 둘은 system tool이다. 둘 중 하나가 없으면 machine이 blocked 또는 damaged 상태라고
본다. Shell replacement를 설치하려고 하지 않는다.

### curl

`curl`은 Bun과 Hermes installer에 필요하다. 없으면 blocking state를 기록한다. 이
flow에서 curl을 따로 설치하지 않는다.

### git and Command Line Tools

Step 3는 GBrain source repo clone/reuse와 docs snapshot을 위해 `git`이 필요하다.

Command Line Tools 또는 usable `git`이 없으면 먼저 사용자에게 macOS Command Line
Tools 설치 창이 열릴 것이고 설치를 승인해야 한다고 설명한 뒤 다음을 trigger한다:

```bash
xcode-select --install
```

그 뒤 사용자가 macOS installer UI를 완료하고 preflight를 다시 실행할 때까지
`waiting_for_user`를 report한다.

### Node and npm

Node/npm은 OpenClaw branch에서만 필요하다.

OpenClaw가 선택됐고 Node/npm이 없으면 official Node.js macOS pkg path로 설치한다.
결과는 Zebra 안에서만이 아니라 일반 terminal에서도 사용할 수 있어야 한다.

### Bun

Bun은 Step 3 GBrain setup에 필요하다. 없으면 official Bun installer로 설치한다.

### OpenClaw

OpenClaw는 사용자가 OpenClaw를 선택했고 설치되어 있지 않을 때만 설치한다. 설치 명령:

```bash
npm install -g openclaw
```

### Hermes

Hermes는 사용자가 Hermes를 선택했고 설치되어 있지 않을 때만 설치한다. Dynamic flag
discovery 없이 검증된 minimal Hermes installer command를 사용한다.

## State File

Step 2 state 위치:

```text
~/Library/Application Support/zebra/onboarding/gbrain-runtime-state.json
```

State에는 다음을 포함한다:

```text
schemaVersion
progress
preflight
attempts
selection
receipt
```

`progress`에는 다음을 포함한다:

- current section
- completed sections
- waiting-for-user reason
- last failure

`preflight`에는 fact와 detection timestamp를 포함한다.

`attempts`에는 다음을 포함한다:

- attempted command
- started/finished timestamp
- exit code
- stdout tail
- stderr tail
- recoverable flag
- blocking reason

`selection`에는 다음을 포함한다:

- selected runtime
- selected provider when chosen

`receipt`에는 다음을 포함한다:

- complete
- runtime
- executable path
- version
- provider
- key source
- config paths
- checks
- verified timestamp
- reasons

## 사람 검증용 요약

이 섹션은 설계 의도가 대략 맞는지 빠르게 확인하기 위한 요약이다.

- Step 1은 agent-driven 작업 전에 global primary agent CLI를 먼저 bootstrap한다.
- Step 2는 primary-agent orchestrated flow다. Agent가 이 고정 문서를 읽고
  helper/report command를 호출한다.
- Step 2는 run-specific packet을 만들지 않는다.
- Step 2는 GBrain source repo를 prepare/clone/install하지 않는다.
- Step 3는 `activeGBrainBinding.sourceRepoPath`, GBrain repo clone/reuse, docs
  snapshot, `bun install`, `bun install -g .` 또는 `bun link`, `gbrain --version`을
  계속 담당한다.
- Preflight는 넓게 감지하지만 아무것도 설치하지 않는다.
- Recovery는 선택된 경로에 필요한 것만 설치한다.
- `npm`이 없어도 OpenClaw가 선택되기 전에는 문제가 아니다.
- Zebra는 Python을 설치하지 않는다. 기존 macOS/CLT `python3`를 사용한다.
- CLT/git recovery는 `xcode-select --install`이고, 이후 user-waiting/blocking
  상태가 된다.
- Node/npm recovery는 official Node.js macOS pkg를 사용한다. Homebrew도 아니고
  Zebra-private runtime도 아니다.
- Bun recovery는 official Bun installer를 사용한다.
- OpenClaw install은 `npm install -g openclaw`를 유지하되, npm global prefix가
  root-owned/write 불가면 먼저 `npm config set prefix "$HOME/.local"`을 적용한다.
- Hermes install은 이미 검증된 minimal installer command를 유지한다.
- Step 2 완료 기준은 binary 존재 여부가 아니라 `gbrain-runtime-state.json`의 runtime
  receipt다.
