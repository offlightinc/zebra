# Zebra OpenClaw/Hermes Minimal Install Script Plan

[Source: Codex session `/Users/han/.codex/sessions/2026/06/05/rollout-2026-06-05T10-09-28-019e9553-f8e8-7930-8d69-6a32623c2d89.jsonl`, 2026-06-05]

## Summary

Zebra onboarding에 새 2단계를 추가한다. 기존 2단계였던 `gbrain` 설치는 3단계로 밀고, 나머지 단계도 하나씩 뒤로 민다.

새 2단계는 OpenClaw 또는 Hermes를 "풀 연동"하는 단계가 아니다. 목표는 `gbrain` 설치 전에 사용자가 선택한 agent runtime이 최소한 LLM을 호출할 수 있는 상태인지 확인하고, 필요한 경우 Zebra가 가장 작은 범위로 설치와 설정을 완료하는 것이다.

이 단계는 agent에게 설치를 위임하지 않는다. Zebra-owned script/helper가 설치 여부 확인, 최소 설치, API 설정, 검증, receipt 기록을 직접 수행한다. agent는 실패 복구나 사용자가 직접 판단해야 하는 상황에서만 보조로 연다.

## Onboarding Step Changes

변경 후 단계:

1. 언어 모델 에이전트 CLI 스캔 및 primary agent 선택
2. OpenClaw/Hermes 실행 준비
3. `gbrain` 설치 및 연결
4. `gbrain-adapter` 설치
5. Source Onboarding으로 이메일/문서/메시지 같은 사용자 source를 brain에 주입
6. goals/tasks 사용 흐름 확인

2단계 완료 기준은 OpenClaw/Hermes 전체 연동 완료가 아니라 다음 receipt가 검증된 상태다.

- 선택한 runtime: `openclaw` 또는 `hermes`
- CLI 설치 여부 및 version
- LLM provider/model 설정
- API key 존재 여부 또는 key reference
- 최소 smoke test 결과
- secret을 제외한 receipt 저장

## Helper Contract

새 helper 이름 후보:

```text
zebra-gbrain-runtime-onboarding
```

역할:

- `detect`: OpenClaw/Hermes 설치 여부 확인
- `choose`: 현재 상태별 선택지 출력
- `install`: 선택한 runtime 최소 설치
- `configure`: LLM 호출에 필요한 provider/config 작성
- `verify`: CLI/config/API smoke test 검증
- `status`: UI/debug용 JSON 출력
- `receipt`: 완료 기록 출력

state/receipt 위치:

```text
~/Library/Application Support/zebra/onboarding/gbrain-runtime-state.json
```

secret은 저장하지 않는다. 저장 가능한 값은 `provider`, `model`, `keySource`, `runtime`, `executablePath`, `version`, `configPath`, `verifiedAt`, check 결과뿐이다.

## Minimal Install Policy

OpenClaw는 OpenClaw 전체 onboarding을 돌리더라도 daemon, plugin, channel, skills, bootstrap 계열을 skip하고 모델 auth/API 설정 중심으로 제한한다.

예상 방향:

```bash
npm install -g openclaw@latest

openclaw onboard --non-interactive \
  --mode local \
  --auth-choice apiKey \
  --skip-daemon \
  --skip-plugin \
  --skip-channels \
  --skip-skills \
  --skip-bootstrap \
  --json
```

구현 시점에는 현재 OpenClaw source의 실제 flag 이름과 fresh install 동작을 다시 검증한다. 제품 요구사항은 flag 문자열 자체가 아니라 "daemon/plugin/channel/skills/bootstrap을 설치하지 않고 LLM 호출 가능 상태까지만 준비한다"는 동작이다.

Hermes는 installer로 CLI만 설치하고 browser/setup/skills를 피한다.

예상 방향:

```bash
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash -s -- \
  --skip-setup \
  --skip-browser \
  --no-skills \
  --non-interactive
```

그 뒤 Zebra가 config/API key만 채운다. Portal OAuth, browser setup, OpenClaw migration, secret migration, skills/plugin 연동은 기본 2단계 범위가 아니다.

## User Notice Copy

사용자에게 내부 workspace/profile/agentDir 같은 세부 구조를 설명하지 않는다. 핵심 고지만 한다.

공통 문구:

```text
gbrain은 OpenClaw 또는 Hermes를 통해 동작할 수 있습니다.
이미 사용 중인 OpenClaw/Hermes를 선택하면 gbrain 실행에 필요한 파일이나 설정이 추가 또는 변경될 수 있습니다.
기존 설정을 그대로 두고 싶다면, 설치되어 있지 않은 다른 쪽을 새로 설치해 gbrain에 사용할 수 있습니다.
```

상태별 선택지:

### OpenClaw만 설치됨

```text
OpenClaw가 설치되어 있습니다.
gbrain에 OpenClaw를 사용할 수 있습니다. 이 경우 gbrain 실행에 필요한 파일이나 설정이 OpenClaw 쪽에 추가 또는 변경될 수 있습니다.
기존 OpenClaw 설정을 그대로 두고 싶다면 Hermes를 설치해 gbrain에 사용할 수 있습니다.
```

선택지:

- OpenClaw 사용
- Hermes 설치 후 사용

### Hermes만 설치됨

```text
Hermes가 설치되어 있습니다.
gbrain에 Hermes를 사용할 수 있습니다. 이 경우 gbrain 실행에 필요한 파일이나 설정이 Hermes 쪽에 추가 또는 변경될 수 있습니다.
기존 Hermes 설정을 그대로 두고 싶다면 OpenClaw를 설치해 gbrain에 사용할 수 있습니다.
```

선택지:

- Hermes 사용
- OpenClaw 설치 후 사용

### OpenClaw와 Hermes 둘 다 설치됨

```text
OpenClaw와 Hermes가 설치되어 있습니다.
gbrain에 사용할 agent를 선택하세요. 선택한 쪽에는 gbrain 실행에 필요한 파일이나 설정이 추가 또는 변경될 수 있습니다.
```

선택지:

- OpenClaw 사용
- Hermes 사용

### 둘 다 설치되어 있지 않음

```text
gbrain은 OpenClaw 또는 Hermes를 통해 동작할 수 있습니다.
사용할 agent를 선택하면 Zebra가 최소 설치와 gbrain 실행 준비를 진행합니다.
```

선택지:

- OpenClaw 설치
- Hermes 설치

사용자-facing 문구에서는 다음 표현을 쓰지 않는다.

- "전용 환경"
- "새 워크스페이스 연결"
- "OpenClaw agent 추가"
- "Hermes profile 분리"
- "agent 환경을 하나 더 관리"

## Implementation Notes

`gbrain` 원문에는 Zebra식 OpenClaw/Hermes 선택 flow가 없다. 이 preflight와 선택지는 Zebra가 추가하는 제품 흐름이다.

OpenClaw 쪽은 `gbrain`이 OpenClaw를 등록해서 쓰는 것이 아니라, OpenClaw가 `gbrain` skillpack/MCP/tool backend를 쓰도록 준비하는 구조다. Hermes도 `gbrain`이 Hermes profile 정보를 직접 받아가는 구조로 설명하면 안 된다.

`gbrain skillpack scaffold` 자체는 기존 파일을 덮어쓰지 않는 원칙이 있지만, setup skill 흐름에서는 `AGENTS.md` 또는 equivalent에 `gbrain` 규칙을 추가/변경할 수 있다. 그래서 사용자 고지는 "파일이나 설정이 추가 또는 변경될 수 있음"으로 유지한다.

## Test Plan

- checklist step count가 7개이고 `gbrain` 단계가 3번으로 표시되는지 검증
- OpenClaw only, Hermes only, both installed, none installed 상태별 선택지 검증
- 기존 runtime 선택 시 설치 명령 없이 configure/verify로 진행하는지 검증
- 미설치 runtime 선택 시 install -> detect -> configure -> verify 순서 검증
- receipt에 secret 값이 저장되지 않는지 검증
- verify 실패 시 checklist가 checked 되지 않고 복구 안내로 남는지 검증

## Assumptions

- 제품명은 `gbrain`으로 쓴다.
- 2단계 기본 추천 runtime은 두지 않는다.
- 사용자가 기존 OpenClaw/Hermes를 쓰는 경우에도 Zebra는 먼저 설치 여부를 확인한다.
- 2단계의 사용자-facing 이름은 `OpenClaw/Hermes 실행 준비`로 둔다. 내부 완료 범위는 OpenClaw/Hermes가 LLM을 호출할 수 있는 최소 상태까지다.
- plugin, skills, daemon, channel, bootstrap, browser/OAuth 연동은 `gbrain` 설치 단계 또는 후속 단계에서 필요할 때만 다룬다.
