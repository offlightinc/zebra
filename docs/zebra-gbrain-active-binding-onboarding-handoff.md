# Zebra GBrain Step 3 Repo-First Handoff

이 문서는 다음 세션에서 이어서 진행할 핵심만 남긴다.

## 핵심 결정

Step 2는 건드리지 않는다.

- Step 2는 기존 OpenClaw/Hermes runtime 준비/probe 역할만 유지한다.
- Step 2에 GBrain repo clone, repo 선택, `bun install`, `gbrain init`, source
  registration 같은 책임을 추가하지 않는다.

Step 3에서 GBrain repo-first flow를 수행한다.

- Step 3 시작 시 script/helper가 GBrain source repo 위치를 먼저 확정한다.
- 기본 추천 위치는 upstream 문서 흐름에 맞춘 `~/gbrain`이다.
- 확정된 repo 위치를 Step 3 state/receipt에 active GBrain source binding으로 기록한다.
- OpenClaw/Hermes 중 선택된 runtime을 이 repo를 `cwd`로 해서 실행한다.
- 그 runtime 안에서 repo-local `bun install`을 수행한다.
- 이후 기존 Step 3 GBrain setup 흐름을 같은 cwd/binding 상태에서 이어간다.

## Repo 위치 결정 흐름

Step 3 script/helper는 먼저 홈 디렉토리 기준으로 확인한다.

1. `~/gbrain`이 valid GBrain repo이면
   - 사용자에게 이 repo를 사용할지 확인한다.
   - 확인되면 active GBrain source binding으로 기록한다.

2. `~/gbrain`이 없거나 빈 디렉토리이면
   - `~/gbrain`에 GBrain repo를 clone하는 것을 추천한다.
   - 사용자가 동의하면 clone하고 active GBrain source binding으로 기록한다.

3. `~/gbrain`이 존재하지만 valid GBrain repo가 아니면
   - 자동으로 덮어쓰거나 삭제하지 않는다.
   - 사용자에게 선택지를 준다:
     - 이 경로를 비우거나 백업한 뒤 `~/gbrain`에 다시 진행
     - 다른 GBrain source repo 위치 선택

4. 사용자가 custom path를 선택하면
   - broad filesystem scan은 하지 않는다.
   - 사용자가 선택한 path만 검사한다.
   - 없거나 비어 있으면 clone한다.
   - valid GBrain repo이면 reuse한다.
   - path가 비어 있지 않고 valid GBrain repo도 아니면 자동으로 지우거나 덮어쓰지 않는다.
     사용자에게 다음 중 하나를 고르게 한다:
     - 이 path 아래 새 하위 디렉토리(예: `<path>/gbrain`)를 만들어 거기에 clone
     - 이 path를 비우거나 백업한 뒤 같은 path에 clone
     - 다른 path 선택

## Step 3 Runtime Flow

repo 위치가 확정된 뒤:

1. script/helper가 active binding을 기록한다.
2. OpenClaw/Hermes 중 선택된 runtime을 실행한다.
3. runtime의 `cwd`는 active GBrain source repo여야 한다.
4. runtime은 그 repo 안에서 `bun install`을 실행한다.
5. 같은 repo에서 `bun link` 또는 동등한 wrapper를 설정해 `gbrain` CLI가 active repo를
   가리키게 만든다. custom path를 선택한 경우에는 이 단계가 필수다.
6. `gbrain --version`을 실행해 CLI가 사용 가능함을 확인하고, 가능하면 active repo와
   연결된 executable인지 기록한다.
7. 기존 Step 3의 `INSTALL_FOR_AGENTS.md` 기반 GBrain setup을 이어간다.

## 유지할 원칙

- `~/gbrain`은 암묵적 fallback이 아니라 기본 추천값이다.
- `~/.gbrain`은 source repo가 아니라 GBrain config/DB 위치다.
- source repo 위치와 config/DB boundary를 섞지 않는다.
- occupied invalid path는 자동 삭제/덮어쓰기하지 않는다.
- repo-local `bun install`은 Step 3에서 OpenClaw/Hermes가 repo cwd에서 수행한다.
- Step 3의 이후 명령들이 `gbrain` CLI를 호출하므로, active repo에서 `bun link` 또는
  동등한 wrapper를 설정하고 `gbrain --version`으로 확인해야 한다.
