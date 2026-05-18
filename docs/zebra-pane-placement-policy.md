# Zebra Pane Placement Policy

## 목적

Zebra 사이드바의 goal/task markdown, email row, 그리고 Markdown Chat Pill이 각각 새 패널을 열 때 어디에 열릴지 정한다.

핵심 원칙은 다음 세 가지다.

1. 화면을 좁히는 split은 가능한 한 만들지 않는다.
2. Chat Pill로 만든 agent companion pane에는 content를 자동으로 섞지 않는다.
3. pane에 영구 role을 붙이지 않고, 현재 layout을 보고 매번 가장 자연스러운 위치를 고른다.

## 용어

### Content panel

사용자가 읽거나 편집하는 대상이다.

- MarkdownPanel
- ZebraEmailThreadPanel
- FilePreviewPanel

### Agent companion pane

Markdown Chat Pill이 만든 agent terminal tab들이 쌓이는 pane이다.

현재 구현 기준으로는 `MarkdownPanelController.chatCompanionPaneId`에 저장된 pane이다.

중요한 점은 이 값이 "영구적인 pane role"은 아니라는 것이다. 사용자가 tab을 옮기거나 pane을 닫을 수 있으므로, 라우팅할 때마다 현재 layout에 실제로 존재하는지 다시 확인해야 한다.

### Content open action

사이드바에서 goal/task markdown 파일이나 email thread를 클릭해서 content를 여는 행동이다.

### Agent open action

Markdown Chat Pill에서 프롬프트를 제출해서 agent terminal을 여는 행동이다.

## 고정 규칙

### 1. Chat Pill은 같은 문서에서 같은 companion pane을 유지한다

같은 MarkdownPanel에서 Chat Pill을 계속 사용하면, terminal tab은 같은 companion pane에 쌓인다.

```text
[Weekly.md] --Chat Pill--> [Weekly.md] [Codex terminal]
[Weekly.md] --Chat Pill--> [Weekly.md] [Codex terminal + Claude terminal]
```

알고리즘:

```text
1. source MarkdownPanel의 controller.chatCompanionPaneId가 있는지 본다.
2. 해당 pane이 현재 workspace layout에 아직 존재하면 거기에 새 terminal tab을 만든다.
3. 없으면 source MarkdownPanel 기준 오른쪽에 새 terminal split을 만든다.
4. 새 terminal pane id를 controller.chatCompanionPaneId에 저장한다.
```

이 규칙은 유지한다. content placement 정책이 Chat Pill의 이 동작을 바꾸면 안 된다.

### 2. Content open은 split보다 기존 pane 재사용을 우선한다

goal/task markdown 또는 email을 클릭할 때는 기존 pane에 tab으로 여는 것을 우선한다.

새 split은 기존 pane 중 content를 자동으로 넣을 수 있는 후보가 하나도 없을 때만 만든다.

### 3. Agent companion pane은 content 후보에서 제외한다

Content open action은 Chat Pill agent companion pane을 자동 target으로 쓰지 않는다.

이는 금지된 사용자 상태가 아니라 자동 라우팅 정책이다. 사용자가 직접 tab을 옮겨 content와 agent terminal을 섞는 것은 막지 않는다.

## Content Open 알고리즘

대상: goal/task markdown 클릭, email thread 클릭.

```text
resolvePaneForContentOpen(kind, targetId, anchorPanelId):

1. 같은 target이 이미 열려 있으면 해당 panel을 focus하고 끝낸다.

2. 현재 workspace의 모든 pane을 훑는다.

3. Chat Pill agent companion pane은 후보에서 제외한다.

4. 남은 pane에 점수를 매긴다.

5. 후보 pane이 하나 이상 있으면 점수가 가장 높은 pane에 content tab을 만든다.

6. 후보 pane이 하나도 없으면 새 split을 만든다.
   이 경우 현재 layout에 agent companion pane만 남아 있다는 뜻이다.
   새 content pane은 agent companion pane의 왼쪽에 만든다.
```

## Content Pane 점수 규칙

점수는 "어디에 열면 사용자가 덜 놀라는가"를 고르는 힌트다.

| 조건 | 점수 |
|---|---:|
| 같은 target이 이미 열려 있음 | 즉시 focus |
| 같은 종류 content가 있는 pane | +100 |
| 다른 content가 있는 pane | +70 |
| 일반 terminal 또는 mixed pane | +30 |
| anchor panel이 속한 pane | +10 |
| Chat Pill agent companion pane | 후보 제외 |

동점이면 현재 layout 순서를 기준으로 먼저 나오는 pane을 고른다.

### 같은 종류 content

- markdown 클릭이면 MarkdownPanel이 있는 pane
- email 클릭이면 ZebraEmailThreadPanel이 있는 pane

### 다른 content

- markdown 클릭 시 email/file preview pane
- email 클릭 시 markdown/file preview pane

### 일반 terminal 또는 mixed pane

Agent companion으로 기록되지 않은 terminal pane이다.

Content pane이 하나도 없을 때는 새 split보다 기존 일반 terminal pane에 tab을 추가하는 것이 우선이다.

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

추가할 resolver는 고정 role 저장소가 아니라 현재 layout을 평가하는 함수여야 한다.

예상 형태:

```swift
enum ZebraContentPlacementKind {
    case markdown
    case email
}

func resolvePaneForContentOpen(
    kind: ZebraContentPlacementKind,
    targetId: String,
    anchorPanelId: UUID?
) -> PaneID?
```

Chat Pill 쪽은 기존 `chatCompanionPaneId` 규칙을 유지한다.

Content open 쪽만 이 resolver를 사용해서 agent companion pane을 자동 후보에서 제외한다.

