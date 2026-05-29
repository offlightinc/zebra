# Zebra Pane Placement Policy

## 목적

Zebra 사이드바의 goal/task markdown, email row, 그리고 Zebra-owned agent launcher가 각각 새 패널을 열 때 어디에 열릴지 정한다.

핵심 원칙은 다음 세 가지다.

1. 화면을 좁히는 split은 가능한 한 만들지 않는다.
2. Zebra-owned agent terminal pane에는 content를 자동으로 섞지 않는다.
3. pane에 영구 role을 붙이지 않고, 현재 layout을 보고 매번 가장 자연스러운 위치를 고른다.

## 용어

### Content panel

사용자가 읽거나 편집하는 대상이다.

- MarkdownPanel
- ZebraEmailThreadPanel
- FilePreviewPanel

### Agent companion pane

Zebra가 agent 용도로 연 terminal tab들이 쌓이는 pane이다.

현재 구현 기준으로는 `ZebraAgentTerminalRegistry`가 agent terminal panel id를 표시하고, 현재 layout에서 그 terminal panel이 들어 있는 pane을 역산한다.

Registry에 표시되는 launch source는 다음을 포함한다.

- Markdown Chat Pill
- Email Chat Pill
- Clawvisor onboarding
- Brain sync failure/debug resolve agent

중요한 점은 pane 자체에 "영구적인 role"을 붙이지 않는다는 것이다. 사용자가 tab을 옮기거나 pane을 닫을 수 있으므로, 라우팅할 때마다 현재 layout을 다시 보고 registry에 표시된 agent terminal panel이 들어 있는 pane인지 확인해야 한다.

### Content open action

사이드바에서 goal/task markdown 파일이나 email thread를 클릭해서 content를 여는 행동이다.

### Agent open action

Zebra UI에서 agent terminal을 여는 행동이다. Chat Pill, Clawvisor onboarding, Brain sync failure/debug resolve가 여기에 포함된다.

## 고정 규칙

### 1. Chat Pill은 같은 content pane 오른쪽의 marked agent companion pane만 재사용한다

Chat Pill은 현재 content pane 오른쪽에 이미 registry-marked agent terminal pane이 있으면 거기에 새 terminal tab을 쌓는다. 일반 terminal pane은 자동 companion pane으로 취급하지 않는다.

```text
[Weekly.md] --Chat Pill--> [Weekly.md] [Codex terminal]
[Weekly.md] --Chat Pill--> [Weekly.md] [Codex terminal + Claude terminal]
```

알고리즘:

```text
1. 현재 content pane 오른쪽의 candidate pane들을 layout에서 찾는다.
2. candidate pane 안에 ZebraAgentTerminalRegistry에 표시된 terminal panel이 있으면 거기에 새 terminal tab을 만든다.
3. 없으면 source content panel 기준 오른쪽에 새 terminal split을 만든다.
4. 새 terminal panel id를 registry에 표시하고 source(markdown file/email thread)와 agent를 함께 저장한다.
```

이 규칙은 유지한다. content placement 정책이 Chat Pill의 이 동작을 바꾸면 안 된다.

### 1-1. Agent launcher는 공통 placement 정책을 탄다

Chat Pill과 Clawvisor onboarding / Brain sync failure/debug resolve는 시작 기준만 다르다.
Chat Pill은 source content pane 기준이고, standalone launcher는 focused pane 기준이다.
terminal 생성, registry mark, startup command 전송은 같은 launcher가 처리한다.

Standalone launcher는 다음 순서로 열린다.

```text
1. focused pane이 이미 agent companion pane이면 그 pane에 terminal tab을 추가한다.
2. focused pane 오른쪽에 registry-marked agent companion pane이 있으면 그 pane을 재사용한다.
3. focused pane이 terminal-only 중립 pane이면 그 pane에 terminal tab을 추가한다.
4. 아니면 focused pane 오른쪽에 새 agent split을 만든다.
```

즉, 앱 첫 시작의 빈 terminal pane은 새 split 없이 agent 실행 위치로 쓸 수 있다. 반면
focused pane이 markdown/email content pane이면 onboarding/debug terminal tab을 직접 추가하지
않는다. content pane 안에 marked terminal을 넣으면 content pane 전체가 agent pane으로
분류되는 부작용이 생기기 때문이다.

### 2. Content open은 split보다 기존 pane 재사용을 우선한다

goal/task markdown 또는 email을 클릭할 때는 기존 pane에 tab으로 여는 것을 우선한다.

새 split은 기존 pane 중 content를 자동으로 넣을 수 있는 후보가 하나도 없을 때만 만든다.

### 3. Agent companion pane은 content 후보에서 제외한다

Content open action은 agent companion pane을 자동 target으로 쓰지 않는다.

이는 금지된 사용자 상태가 아니라 자동 라우팅 정책이다. 사용자가 직접 tab을 옮겨 content와 agent terminal을 섞는 것은 막지 않는다.

## Content Open 알고리즘

대상: goal/task markdown 클릭, email thread 클릭.

```text
openContentFromSidebar(target, requestedPane):

1. 같은 target이 이미 agent companion pane 밖에 열려 있으면 해당 panel을 focus하고 끝낸다.

2. 원래 사이드바 target pane을 정한다.
   Markdown/email sidebar click 기준으로는 focusedPaneId가 있으면 그 pane,
   없으면 layout의 첫 pane이다.

3. 원래 target pane이 agent companion pane이 아니면 그 pane을 사용한다.

4. 원래 target pane이 agent companion pane이면 layout의 첫 번째 non-agent pane으로 대체한다.

5. non-agent pane이 하나도 없으면 새 split을 만든다.
   이 경우 현재 layout에 agent companion pane만 남아 있다는 뜻이다.
   새 content pane은 agent companion pane의 왼쪽에 만든다.
```

이 정책은 pane 후보에 점수를 매기지 않는다. 같은 종류 content pane을 일부러 찾아가거나,
anchor panel 때문에 점수를 더 주는 동작도 없다.

최종 target pane 안에서 기존 selected MarkdownPanel을 파일만 바꿔 재사용할지,
새 Markdown tab을 만들지는 기존 cmux markdown open 규칙을 따른다. Email도 동일하게
최종 target pane 안의 email panel 재사용 여부만 본다.

### 일반 terminal 또는 mixed pane

Agent companion으로 기록되지 않은 terminal pane이다.

이 pane이 원래 사이드바 target이면 content tab을 추가할 수 있다. 새 split보다 기존
target pane을 유지하는 것이 우선이다.

## Split 생성 조건

Content open action에서 split을 만드는 조건은 하나다.

```text
agent companion이 아닌 후보 pane이 하나도 없을 때
```

즉, workspace가 다음처럼 agent companion pane만 가진 경우다.

```text
Before:
[Codex terminal(agent companion)]

Email 클릭

After:
[Email] [Codex terminal(agent companion)]
```

이때는 content와 agent terminal을 자동으로 섞지 않기 위해 split을 만든다. 새 content pane은 왼쪽, agent companion pane은 오른쪽에 둔다.

구현상으로는 agent companion pane 기준 horizontal split을 만들고 `insertFirst = true`를 사용한다.

## 예시

### 기존 content pane이 있을 때

```text
Before:
[Weekly.md] [Codex terminal(agent companion)]

Email 클릭

After:
[Weekly.md + Email tab] [Codex terminal(agent companion)]
```

새 split을 만들지 않는다. 기존 content pane을 재사용한다.

### content pane이 없고 일반 terminal pane이 있을 때

```text
Before:
[Terminal] [Codex terminal(agent companion)]

Email 클릭

After:
[Terminal + Email tab] [Codex terminal(agent companion)]
```

일반 terminal pane은 agent companion이 아니므로 후보가 된다.

### pane이 하나이고 일반 terminal일 때

```text
Before:
[Terminal]

Email 클릭

After:
[Terminal + Email tab]
```

split하지 않는다.

### pane이 하나이고 agent companion일 때

```text
Before:
[Codex terminal(agent companion)]

Email 클릭

After:
[Email] [Codex terminal(agent companion)]
```

agent companion pane에는 content를 자동으로 섞지 않는다. 이 경우에만 split한다.

### 같은 target이 이미 열려 있을 때

```text
Before:
[Weekly.md] [Email A]

Email A 클릭

After:
[Weekly.md] [Email A focused]
```

중복 tab을 만들지 않는다.

## Recent content pane 기록은 v1에서 쓰지 않는다

별도의 `recentContentPaneId` 같은 기억값은 v1 정책에서 제외한다.

이유:

- 사용자가 tab을 옮기거나 pane을 닫으면 stale해질 수 있다.
- 현재 layout만 봐도 충분히 자연스러운 선택을 할 수 있다.
- 자율성을 주려면 오래된 기억보다 현재 사용자가 만든 상태를 우선해야 한다.

필요해지면 후속으로 "최근 사용 pane"을 추가할 수 있지만, 그때도 현재 layout 검증을 먼저 통과해야 한다.

## 구현 메모

Content open 쪽에는 점수 기반 resolver를 두지 않는다. 사이드바가 넘긴 원래 target pane을
받고, 그 pane이 agent companion이면 첫 번째 non-agent pane으로 바꾸는 작은 guard만 둔다.

Agent launch 쪽은 `ZebraAgentTerminalRegistry`의 terminal panel marker와 현재 layout을 함께 사용한다.

Content open 쪽은 같은 registry marker를 읽어서 agent companion pane을 자동 target에서 제외한다.
