# Zebra Gmail 스레드 상세 보기 계획

상태: 초안
담당: Zebra
최종 수정: 2026-05-17

## 요약

Zebra에는 이미 Gmail 사이드바 목록이 있지만, 현재 목록 데이터는 스레드
메타데이터만 가지고 있다. 다음 단계는 사용자가 Gmail 목록 row를 클릭했을 때
중앙 패널에서 해당 스레드의 본문을 안전하게 보여주는 것이다.

이 계획은 Conclave의 이메일 상세 보기 구현을 제품/구현 레퍼런스로 삼는다.

- `EmailDetailPanel.tsx`: 스레드 단위 상태, 로딩/에러 처리, 기본 펼침 메시지.
- `ThreadMessageCard.tsx`: 접힘/펼침 메시지 카드와 격리된 HTML 렌더링.
- `htmlUtils.ts`: 이메일 HTML shell CSS와 rich email 감지.
- `gmail-message-parser.ts`: Gmail MIME payload 파싱, base64url decoding,
  `text/plain`/`text/html` 추출.

Zebra 구현은 cmux upstream 변경을 최소화해야 한다. 기본 목표는 중앙 Bonsplit
영역에 Zebra 소유의 이메일 상세 패널을 여는 것이다. 기존 패널 렌더러가 Zebra
factory를 받을 수 있도록 작은 cmux seam만 추가한다. 구현 중 이 seam이 지나치게
넓어진다면 fallback으로 BrowserPanel에 backend viewer URL을 여는 방식을 쓸 수
있지만, 기본 계획은 읽기 전용 전용 이메일 패널이다.

## 현재 상태

### Zebra

- 사이드바 UI는 `Packages/ZebraVault/Sources/ZebraVault/VerticalTabsSidebar/`
  아래에 있다.
- 이메일 목록 row는 `VerticalTabsSidebar/Email/EmailListView.swift`의
  `EmailThreadItem`을 사용한다.
- Desktop API client는 `Sources/Zebra/Environment/ZebraServices.swift` 안의
  `ZebraGmailAPIClient`로 존재한다.
- Backend list/status/sync route는 `web/app/api/gmail` 아래에 있다.
- Backend Gmail service는 현재 `gmail.metadata` scope를 요청하고 메시지
  metadata만 가져온다.
- `email_threads`는 목록용 필드만 저장한다:
  subject, latest message id, sender, timestamp, snippet, labels, attachment flag.

### Conclave 참고점

Conclave는 메시지 본문을 `email_messages.body_text/body_html`에 저장하고, 상세
뷰는 local DB를 먼저 읽은 뒤 backend fallback을 사용한다. Zebra v1은 Conclave의
전체 offline-first pipeline까지 복사할 필요는 없지만, 아래 동작은 참고한다.

- 스레드 상세 shape: `messages[]` 안에 `bodyText`, `bodyHtml`, sender,
  timestamp, labels, unread state 포함.
- 기본 펼침: 기존 expanded id를 유지할 수 있으면 유지하고, 없으면 unread
  메시지와 최신 메시지를 펼친다.
- HTML 렌더링: 신뢰할 수 없는 이메일 HTML을 web view shell 안에 격리하고,
  이미지/테이블 폭을 제한하며, preformatted text를 wrap하고, 링크 클릭을
  intercept한다.
- Plain text fallback: HTML이 없거나 실제 HTML이 아니면 `bodyText`를 보여준다.

## 요구사항

1. 사이드바 이메일 row를 클릭하면 중앙 패널에 해당 스레드가 열린다.
2. 상세 패널은 스레드 subject header와 메시지 카드 목록을 보여준다.
3. HTML 이메일 본문은 앱 UI를 침범하지 않도록 안전하게 렌더링한다.
4. Plain text 이메일도 읽기 쉬워야 한다.
5. 스레드 메시지는 클릭 시점에 로드하되, 파싱된 본문은 backend DB에 캐시한다.
6. 기존 Gmail metadata 목록 동작은 그대로 유지한다.
7. Zebra 코드는 기본적으로 Zebra 소유 영역에 둔다.
8. cmux upstream touchpoint는 작고 명시적이어야 하며 문서화해야 한다.

## v1 비목표

- Reply, forward, compose, draft autosave.
- 상세 패널에서 archive, mark read, star, label 변경.
- 전체 offline-first 본문 동기화.
- 첨부파일 다운로드/뷰어.
- Gmail remote image proxy.
- 이메일 본문 내 검색.
- Conclave classification summary UI 재사용.

## 핵심 결정

### 상세 조회

새 backend endpoint를 추가한다.

```text
GET /api/gmail/threads/:threadId/messages
```

`threadId`는 현재 `EmailThreadItem.id`로 쓰는 Gmail thread id를 그대로 사용한다.

Endpoint는 Gmail `users.threads.get`을 `format=full`로 호출하고, 각 메시지의
MIME payload를 파싱해 Zebra DTO로 반환한다. Google 문서상 full format은 parsed
body content를 포함하지만 `gmail.metadata` scope에서는 사용할 수 없으므로,
Zebra는 `gmail.readonly`로 scope를 올려야 한다.

참고:

- https://developers.google.com/workspace/gmail/api/reference/rest/v1/users.threads/get
- https://developers.google.com/workspace/gmail/api/auth/scopes

### 저장 정책

v1부터 파싱된 메시지 본문을 backend DB에 캐시한다.

이유:

- Conclave가 이미 속도 때문에 `body_text/body_html` 저장 방식을 선택했고, 이메일
  상세는 같은 스레드를 반복해서 여는 일이 많다.
- Gmail full payload 파싱은 목록 클릭마다 반복하기에는 비용이 크고, 네트워크
  latency도 사용자에게 직접 노출된다.
- 본문은 message 단위 데이터라 `email_threads`에 컬럼을 붙이면 thread 최신
  메시지와 과거 메시지가 섞인다.

따라서 `email_threads`에 본문 컬럼을 추가하지 않고, 새 `email_messages` 테이블을
추가한다. `email_threads`는 목록/스레드 summary의 source of truth로 유지하고,
`email_messages`는 상세 렌더링용 message cache로 둔다.

캐시 정책:

- 목록 sync는 기존처럼 thread metadata를 먼저 빠르게 upsert한다.
- 상세 조회 시 `email_messages`에 해당 thread의 visible message body가 있으면 DB
  cache를 반환한다.
- cache가 없거나 stale이면 Gmail `threads.get(format=full)`을 호출해 parse 후
  `email_messages`를 upsert하고 반환한다.
- stale 기준은 v1에서 단순하게 `email_threads.updated_at > max(email_messages.updated_at)`
  또는 latest message id 불일치로 둔다.
- 본문 저장은 사용자가 Gmail 연결을 끊으면 `email_accounts` cascade로 함께 삭제되게
  한다.

### 렌더링 방식

일반 브라우저 UI가 아니라 Zebra 전용 이메일 패널로 상세를 보여준다. 이렇게 해야
주소창/브라우저 chrome 없이 이메일에 맞는 레이아웃을 만들 수 있다.

구현 선택지:

1. 권장: 작은 cmux panel factory seam을 추가하고, Zebra가 email panel view를
   공급한다.
2. Fallback: panel seam이 너무 커지면 BrowserPanel에 backend viewer URL을 연다.

권장 경로에서도 기존 중앙 패널 메커니즘은 재사용한다.

- `Workspace`의 panel 생성 패턴.
- 기존 Markdown panel view factory와 유사한 `PanelContentView` factory slot 패턴.
- 가능하면 기존 focus flash와 panel lifecycle 개념.

## 공개 인터페이스와 DTO

### Backend response

```ts
type GmailThreadMessagesResponse = {
  threadId: string;
  cached: boolean;
  messages: GmailThreadMessageDTO[];
};

type GmailThreadMessageDTO = {
  messageId: string;
  threadId: string;
  internetMessageId: string | null;
  subject: string | null;
  fromName: string | null;
  fromEmail: string | null;
  to: string | null;
  cc: string | null;
  receivedAt: string | null;
  snippet: string | null;
  labelIds: string[];
  isUnread: boolean;
  isSent: boolean;
  hasAttachment: boolean;
  bodyText: string | null;
  bodyHtml: string | null;
};
```

### Swift model

Zebra 소유 코드에 동일한 의미의 model을 추가한다.

```swift
public struct EmailThreadDetail: Equatable {
    public let threadId: String
    public let cached: Bool
    public let messages: [EmailThreadMessage]
}

public struct EmailThreadMessage: Identifiable, Equatable {
    public let id: String
    public let internetMessageId: String?
    public let subject: String?
    public let fromName: String?
    public let fromEmail: String?
    public let to: String?
    public let cc: String?
    public let receivedAt: Date?
    public let snippet: String?
    public let labelIds: [String]
    public let isUnread: Bool
    public let isSent: Bool
    public let hasAttachment: Bool
    public let bodyText: String?
    public let bodyHtml: String?
}
```

`id`는 Gmail message id다.

## DB schema 계획

새 Drizzle table을 `web/db/schema.ts`에 추가하고, `bunx drizzle-kit generate`로
SQL migration을 생성한다.

권장 table:

```ts
export const emailMessages = pgTable(
  "email_messages",
  {
    id: uuid("id").defaultRandom().primaryKey(),
    userId: text("user_id").notNull(),
    emailAccountId: uuid("email_account_id")
      .notNull()
      .references(() => emailAccounts.id, { onDelete: "cascade" }),
    emailThreadId: uuid("email_thread_id")
      .notNull()
      .references(() => emailThreads.id, { onDelete: "cascade" }),
    gmailThreadId: text("gmail_thread_id").notNull(),
    gmailMessageId: text("gmail_message_id").notNull(),
    internetMessageId: text("internet_message_id"),
    subject: text("subject"),
    snippet: text("snippet"),
    fromName: text("from_name"),
    fromEmail: text("from_email"),
    toRecipients: text("to_recipients"),
    ccRecipients: text("cc_recipients"),
    receivedAt: timestamp("received_at", { withTimezone: true }),
    internalDateMs: text("internal_date_ms"),
    isUnread: boolean("is_unread").notNull().default(false),
    isSent: boolean("is_sent").notNull().default(false),
    hasAttachment: boolean("has_attachment").notNull().default(false),
    labelIds: jsonb("label_ids").$type<string[]>().notNull().default(sql`'[]'::jsonb`),
    bodyText: text("body_text"),
    bodyHtml: text("body_html"),
    bodyFetchedAt: timestamp("body_fetched_at", { withTimezone: true }).notNull().defaultNow(),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
    deletedAt: timestamp("deleted_at", { withTimezone: true }),
  },
  (table) => [
    index("email_messages_account_thread_idx").on(table.emailAccountId, table.gmailThreadId),
    index("email_messages_thread_received_idx").on(table.emailThreadId, table.receivedAt),
    index("email_messages_user_received_idx").on(table.userId, table.receivedAt),
    uniqueIndex("email_messages_account_gmail_message_unique")
      .on(table.emailAccountId, table.gmailMessageId),
  ],
);
```

결정:

- `emailThreadId`는 Zebra 내부 DB의 `email_threads.id` FK다.
- `gmailThreadId`도 중복 저장한다. Gmail API 호출/디버깅/복구에 필요하고, join 없이
  provider id를 확인할 수 있다.
- `gmailMessageId`는 Gmail provider message id다.
- `bodyText/bodyHtml`은 nullable이다. 일부 메시지는 body가 없거나 attachment-only일 수 있다.
- `toRecipients/ccRecipients`는 v1에서 text로 저장한다. 나중에 recipient별 action이
  필요해지면 JSON 배열로 바꿀 수 있지만, 읽기 전용 상세에는 text면 충분하다.
- Soft delete는 `deletedAt`으로 맞춘다. thread가 sync에서 사라지거나 archive/delete
  상태가 반영되면 message도 soft delete할 수 있다.

`email_threads`에 추가할 수 있는 선택 컬럼:

- `bodyCacheStatus`: v1에서는 추가하지 않는다.
- `bodyCachedAt`: v1에서는 `email_messages.body_fetched_at` 집계로 충분하므로 추가하지 않는다.

즉 v1 schema 변경은 `email_messages` table 추가가 기본이고, `email_threads` 컬럼
추가는 하지 않는다.

## Backend 구현 계획

### 1. OAuth scope upgrade

Gmail OAuth scope를 아래에서:

```text
https://www.googleapis.com/auth/gmail.metadata
```

아래로 변경한다:

```text
https://www.googleapis.com/auth/gmail.readonly
```

기존 연결 사용자 처리:

- 상세 fetch에서 Gmail 403 또는 insufficient permissions error가 오면
  `gmail_scope_upgrade_required` 같은 typed error로 반환한다.
- Desktop은 기존 Gmail connect flow를 재사용해 reconnect CTA를 보여준다.

v1은 읽기 전용 상세 보기가 목적이므로 `https://mail.google.com/` full-access
scope는 요청하지 않는다.

### 2. Gmail API client

`web/services/gmail/google.ts`에 함수를 추가한다.

```ts
fetchGmailThread(accessToken: string, threadId: string): Promise<GmailThread>
```

구현 세부사항:

- `/gmail/v1/users/me/threads/{threadId}?format=full` 호출.
- 기존 `gmailGetJSON` error mapping 유지.
- DTO에 필요한 field만 decode/validate.
- 기존 list sync path의 `fetchGmailMessage` metadata 동작은 의도적으로
  refactor하지 않는 한 유지한다.

### 3. Parser

Conclave의 `gmail-message-parser.ts`를 참고해 parser 함수를 추가한다.

- Header name은 case-insensitive로 정규화한다.
- `Subject`, `From`, `To`, `Cc`, `Date`, `Message-ID`를 추출한다.
- sender display name/email을 파싱한다.
- nested MIME parts를 breadth-first 또는 depth-first로 순회한다.
- `bodyHtml`은 정확히 `text/html` part를 우선 사용한다.
- `bodyText`는 `text/plain` part에서 추출한다.
- Gmail body data는 base64url decode한다.
- `text/plain`이 없고 HTML만 있으면 script/style/tag를 제거해 읽기 가능한
  text fallback을 만든다.
- Text fallback은 예를 들어 80,000자 수준으로 cap을 둔다.
- `hasAttachment`는 filename/body attachment id 또는 non-text MIME part로 판정한다.

중요 규칙:

- `bodyHtml`은 decoded value가 실제 HTML처럼 보일 때만 반환한다.
- 그렇지 않으면 text fallback으로 취급한다.

### 4. Workflow

`web/services/gmail/workflows.ts`에 workflow를 추가한다.

```ts
getGmailThreadMessages(input: {
  userId: string;
  request: Request;
  threadId: string;
}): Effect.Effect<GmailThreadMessagesResponse, ...>
```

흐름:

1. 사용자의 연결된 Gmail account를 로드한다.
2. 필요하면 access token을 refresh한다.
3. `email_threads`에서 `gmailThreadId`와 연결된 내부 thread row를 찾는다.
4. `email_messages` cache가 최신이면 cache를 DTO로 map해 반환한다.
5. cache가 없거나 stale이면 Gmail thread full payload를 fetch한다.
6. 메시지들을 parse한다.
7. `internalDate` 기준 오름차순으로 정렬한다.
8. `email_messages`를 upsert한다.
9. DB에 저장된 row를 DTO로 map해 반환한다.

Cache freshness:

- `email_threads.latest_gmail_message_id`가 `email_messages.gmail_message_id` 중
  하나로 존재하지 않으면 stale.
- `email_threads.message_count`보다 visible `email_messages` row 수가 적으면 stale.
  단, 현재 list sync의 `message_count`가 전체 Gmail thread count가 아니라 최근
  fetch 범위 기반이면 이 조건은 보조 신호로만 사용한다.
- `email_messages.body_text/body_html`이 모두 비어 있는 row가 있으면 stale.
- 위 조건이 모두 false이면 cache hit로 처리한다.

Repository 함수:

- `listEmailMessagesForThread({ userId, gmailThreadId })`
- `upsertEmailMessages(rows)`
- `markMissingEmailMessagesDeleted({ emailThreadId, seenGmailMessageIds })`
- `loadEmailThreadByGmailThreadId({ userId, gmailThreadId })`

### 5. Route

아래 route를 추가한다.

```text
web/app/api/gmail/threads/[threadId]/messages/route.ts
```

기존 `withAuthedGmailApiRoute`와 `jsonResponse` helper를 사용한다.

Error 처리:

- Not connected: 기존 `gmail_not_connected`.
- Scope upgrade required: `gmail_scope_upgrade_required`.
- Provider errors: 기존 Gmail provider mapping.
- 비어 있거나 누락된 thread id: 400 JSON error.

## Desktop 및 Zebra 구현 계획

### 1. Client API

`Sources/Zebra/Environment/ZebraServices.swift`의 `ZebraGmailAPIClient`를 확장한다.

```swift
func threadMessages(threadId: String, forceRefresh: Bool = false) async throws -> EmailThreadDetail
```

기존 `status`, `sync`, `startOAuth`, `threads`와 동일하게 auth token header와
`AuthEnvironment.vmAPIBaseURL` 처리 방식을 재사용한다.

### 2. Detail store

Zebra 소유 store를 추가한다. 새 `ZebraEmailDetailStore`를 권장한다. 목록 reload
상태와 상세 상태를 분리하는 편이 안전하다.

상태:

- `selectedThreadId: String?`
- thread별 `ThreadUIState` value: `detail`, `isLoading`, `errorMessage`, `expandedMessageIds`

Action:

- `selectThread(_ thread: EmailThreadItem)`
- `loadThreadIfNeeded(threadId:) async`
- `reloadThread(threadId:forceRefresh:) async`
- `toggleMessage(threadId:messageId:)`
- `clearSelection()`

기본 펼침:

- 기존 expanded id가 아직 존재하면 유지한다.
- 없으면 unread 메시지를 펼친다.
- 최신 메시지는 항상 펼친다.

Desktop cache는 backend DB cache 위의 짧은 UI cache로만 취급한다.

- 앱 실행 중 같은 thread를 다시 열 때 즉시 그린다.
- Refresh 버튼은 backend에 재조회 요청을 보내고, backend가 cache miss/stale이면
  Gmail full payload를 다시 가져온다.
- Desktop에는 본문을 별도 파일이나 SQLite로 저장하지 않는다.

### 3. Sidebar click

`VerticalTabsSidebarEmailContent`와 `EmailListView`에 아래 입력을 추가한다.

```swift
selectedThreadId: String?
onSelectThread: (EmailThreadItem) -> Void
```

`EmailThreadRow` 변경:

- `Button` 또는 `contentShape + onTapGesture`로 row를 clickable하게 만든다.
- selected row chrome을 적용한다.
- hover 동작은 유지한다.
- `LazyVStack` 아래 row는 repository의 list snapshot boundary 규칙에 맞춰
  immutable value와 closure만 받게 한다.

`ZebraSidebarBody` wiring:

1. 선택된 workspace와 pane을 찾는다.
2. email panel opener에 thread open/focus를 요청한다.
3. detail loading을 시작한다.

### 4. Email panel model

Zebra 소유 panel model을 추가한다. 예:

```swift
@MainActor
final class ZebraEmailThreadPanel: Panel, ObservableObject {
    let id: UUID
    let panelType: PanelType = ...
    let threadId: String
    @Published private(set) var displayTitle: String
}
```

`PanelType`은 cmux enum이므로 정확한 seam은 구현 시 결정한다.

- 권장: touchpoint가 충분히 작다면 `.zebraEmail` 또는 generic `.zebra` panel type 추가.
- 낮은 touch 대안: 넓은 변경 없이 도입 가능한 기존 generic panel slot/factory가
  있으면 그것을 사용한다.

`openOrFocusMarkdownSurface`와 유사한 동작을 추가한다.

```swift
openOrFocusEmailThreadSurface(inPane:threadId:subject:focus:)
```

cmux model에 Zebra-only field를 추가하지 않는다.

### 5. Panel view factory

기존 Markdown factory 패턴을 따른다.

- cmux side: `PanelContentView`가 environment factory를 읽는다.
- Zebra side: `ZebraServices.injectIntoEnvironment`가 factory를 설치한다.
- 실제 view는 가능하면 `ZebraVault`에 둔다.
- cmux model conformance가 필요하면 `Sources/Zebra/Adapters/` 아래에 둔다.

새 touchpoint가 필요하면 아래 문서를 함께 갱신한다.

- `docs/upstream-touchpoints.md`
- `docs/upstream-touchpoints.txt`

구현은 먼저 opener와 model을 `Sources/Zebra/**`,
`Packages/ZebraVault/**` 안에 유지하는 방향을 시도한다.

### 6. Email detail view

ZebraVault에 `ZebraEmailThreadDetailView`를 추가한다.

Layout:

- Header:
  - subject
  - message count
  - optional sender/time summary
  - refresh button
- Body:
  - scroll view
  - chronological message cards
  - collapsed card: avatar, sender, snippet, relative time
  - expanded card: sender row, email address, timestamp, body

Message card behavior:

- collapsed card 클릭 시 expand.
- 메시지가 여러 개일 때 collapse button으로 접기.
- label에 `SENT`가 있으면 sender를 "Me"로 표시.
- unread message는 더 강한 typography 또는 작은 dot으로 표시.

Text:

- 모든 user-facing string은 `String(localized:defaultValue:)`를 사용한다.
- 새 key는 `Resources/Localizable.xcstrings`의 Zebra append 영역에 추가한다.

### 7. HTML body view

Conclave iframe 동작을 참고해 WKWebView 기반 body renderer를 추가한다.

입력:

- `bodyHtml`
- theme colors
- link handler closure

Shell:

- `meta charset`
- `meta viewport`
- body padding과 system font
- `img { max-width: 100%; height: auto; }`
- `table { max-width: 100% !important; }`
- `pre { white-space: pre-wrap; word-break: break-word; }`
- `* { box-sizing: border-box; }`
- plain HTML email에만 dark-mode override 적용

보안:

- 이메일 HTML에서 임의 script 실행을 허용하지 않는다.
- `WKNavigationDelegate`에서 link navigation을 intercept한다.
- `http/https` link는 기존 browser/open-url policy로 route한다.
- non-web scheme은 `NSWorkspace.shared.open`으로 route한다.
- 이메일 HTML이 panel 자체를 navigation하지 못하게 한다.

크기:

- 가능하면 content height callback으로 card 높이를 맞춘다.
- SwiftUI 안에서 dynamic WKWebView height가 불안정하면 v1은 expanded card 내부
  web view scroll을 허용한다.

### 8. Plain text body view

사용 가능한 `bodyHtml`이 없으면:

- `bodyText` 또는 `snippet`을 렌더링한다.
- 줄바꿈을 보존한다.
- 가능하면 selectable text로 만든다.
- body와 snippet이 모두 비었을 때만 localized empty content text를 보여준다.

## cmux touchpoints

예상 touchpoint:

- `Sources/Panels/PanelContentView.swift`: email panel view factory 추가/조회.
- `Sources/Workspace.swift`: 기존 Zebra-owned opener seam으로 해결할 수 없을 때만
  email panel open/focus 생성 추가.
- `Sources/Panels/Panel.swift`: panel type이 꼭 필요할 때만 추가.
- `Sources/SessionPersistence.swift`: v1에서 email panel session restore가 반드시
  필요할 때만 추가. 권장은 v1에서 persistence 제외.
- `Resources/Localizable.xcstrings`: Zebra email detail string append.
- `docs/upstream-touchpoints.md`, `.txt`: 새 cmux seam이 생기면 갱신.

구현은 먼저 `Sources/Zebra/**`와 `Packages/ZebraVault/**`에 최대한 머무는 방향으로
진행한다.

## Acceptance criteria

1. Gmail sidebar row 클릭 시 중앙 email detail panel이 열린다.
2. 같은 thread를 다시 클릭하면 무한 duplicate 대신 기존 thread panel을 focus한다.
3. Detail panel은 loading, loaded, error state를 보여준다.
4. Multi-message thread는 chronological order로 렌더링된다.
5. Unread 메시지와 최신 메시지가 기본으로 펼쳐진다.
6. HTML 메시지는 이미지/테이블이 panel width를 넘지 않는다.
7. Plain text 메시지는 HTML artifact 없이 줄바꿈을 유지해 렌더링된다.
8. External link는 email body web view 내부 navigation으로 처리되지 않는다.
9. 첫 상세 조회 후 `email_messages`에 parsed body row가 저장된다.
10. 같은 thread를 다시 열 때 backend가 DB cache를 사용할 수 있다.
11. 기존 Gmail list sync가 계속 동작한다.
12. 기존 Gmail disconnected CTA가 계속 동작한다.
13. 기존 metadata-scope 사용자는 명확한 reconnect path를 본다.

## 검증 계획

Repository 정책상 local E2E/UI test는 실행하지 않는다. 구현 검증은 아래처럼 한다.

1. Build:

   ```bash
   ./scripts/reload.sh --tag gmail-thread-view
   ```

2. Tagged app에서 수동 확인:

   - Gmail disconnected state.
   - Gmail connected list load.
   - 기존 insufficient scope 연결에서 reconnect 표시.
   - One-message thread 클릭 시 상세 열림.
   - Multi-message thread 클릭 시 상세 열림.
   - HTML email이 horizontal overflow 없이 렌더링됨.
   - Plain text email이 줄바꿈을 유지함.
   - Link click이 app/browser policy로 열린다.
   - Refresh가 실패한 detail load를 retry한다.

3. 구현 준비 후 CI/VM에 추가할 테스트:

   - Nested MIME `text/plain`/`text/html` parser unit test.
   - Base64url padding parser unit test.
   - Fake Gmail thread payload 기반 workflow test.
   - `email_messages` upsert idempotency test.
   - Cache hit/miss/stale 판정 test.
   - Default expanded ids에 대한 Swift model/store test.

Source grep만 하는 test는 추가하지 않는다. Parser, workflow, store behavior를 직접
검증하는 테스트만 추가한다.

## Rollout order

1. `email_messages` Drizzle schema와 migration.
2. Backend scope와 parser.
3. Repository cache read/upsert/stale 판정.
4. Backend thread detail route.
5. Desktop client DTO decoding.
6. Detail store와 sidebar row selection.
7. Plain text만 표시하는 최소 중앙 패널.
8. WKWebView HTML body renderer.
9. Default expansion과 selected-row polish.
10. Localization keys.
11. Build 및 수동 검증.
12. 새 cmux seam이 생겼다면 touchpoint 문서 갱신.

## 남은 리스크

- Google OAuth scope upgrade 때문에 사용자가 상세 보기를 위해 재연결해야 할 수 있다.
- 본문 저장은 privacy surface를 키운다. Gmail 연결 해제 시 cascade 삭제가 반드시
  검증되어야 한다.
- DB cache stale 판정이 너무 느슨하면 오래된 본문을 보여줄 수 있다.
- SwiftUI 안에서 WKWebView dynamic height가 불안정할 수 있다. v1에서는 expanded
  card 내부 scroll이 필요할 수 있다.
- First-class panel type을 추가하면 예상보다 많은 cmux 파일을 건드릴 수 있다.
- 이메일 HTML의 remote image가 발신자 URL에서 직접 로드될 수 있다. v1에서는 이
  동작을 명시하거나, privacy 우선이면 remote image를 막아야 한다.
- 매우 큰 thread는 이후 pagination 또는 body truncation이 필요할 수 있다.

## 후속 과제

- Archive/read/star/label action.
- Reply와 draft support.
- Attachment rendering.
- Remote image blocking/proxying.
- Open email panel session restoration.

## 리뷰 피드백 (2026-05-17 append)

아래는 본 plan에 대한 코드 리뷰 결과다. 구현 전에 반드시 lock 해야 할 항목과
권장 보강 사항을 정리한다. 위 본문과 충돌하는 부분은 이 섹션 결정을 우선한다.

### 구현 전 반드시 lock 해야 할 항목

#### 1. Cache stale 판정 로직 단일화

현재 L370~378의 stale 조건 세 가지는 self-contradictory하다.

- "`body_text/body_html`이 모두 비어 있는 row가 있으면 stale" — L269에서 본인이
  "일부 메시지는 body가 없거나 attachment-only일 수 있다"고 인정했다.
  attachment-only 메시지가 하나라도 있는 thread는 영구 stale로 판정돼서
  cache가 무력화된다.
- "`message_count`보다 visible row 수가 적으면 stale" — 본인도 "보조 신호로만
  사용"이라고 인정. stale 판정에서 빼는 게 맞다.

**결정:** stale 기준은 `latest_gmail_message_id`가 `email_messages.gmail_message_id`에
존재하느냐 **하나만** 사용한다. body 없는 row는 `bodyFetchedAt`만 기록하고
stale로 보지 않는다. 진짜로 body를 한 번도 못 받은 케이스를 잡고 싶다면
`body_text IS NULL AND body_html IS NULL AND has_attachment = false`로 좁힌다.

#### 2. Force refresh path 추가

L443~448의 Desktop refresh 버튼은 backend에 재조회만 요청하고 stale 판정은
backend가 한다. cache hit이면 새로고침 눌러도 같은 cache를 돌려준다.

**결정:** route에 `?refresh=1` query param을 받아 stale 판정을 우회한다.
Desktop refresh 버튼은 이 플래그를 항상 set 한다. 자동 재방문 path만 stale
판정에 의존한다.

#### 3. WKWebView 보안 명세 강화

L569~574의 "임의 script 실행을 허용하지 않는다"는 의도만 적혀 있다.
구현 시 다음을 명시적으로 적용한다.

- `WKWebpagePreferences.allowsContentJavaScript = false` (macOS 11+).
- legacy fallback으로 `configuration.preferences.javaScriptEnabled = false`.
- `loadHTMLString` 사용 시 `baseURL = nil` 또는 `about:blank`. http URL을
  baseURL로 주면 remote resource 로드 권한이 풀린다.
- Remote image 정책은 v1에서 lock 한다. 권장: **v1 기본 차단** (CSP `img-src
  data:` 또는 WKWebView content rule로 외부 호스트 block). 추후 옵션화.

#### 4. Detail store state shape을 thread별 value type으로 묶기

상세 상태는 `detailsByThreadId`, `loadingThreadIds`, `errorByThreadId`,
`expandedMessageIdsByThreadId` 같은 여러 dict로 나누지 않는다. 같은 threadId
상태가 여러 저장소에 흩어지면 load/error/expanded state 갱신 순서가 엇갈릴 수
있다.

**결정:**

```swift
struct ThreadUIState: Equatable {
    var detail: EmailThreadDetail?
    var isLoading: Bool
    var errorMessage: String?
    var expandedMessageIds: Set<String>?
}

@MainActor
final class ZebraEmailDetailStore {
    @Published private(set) var selectedThreadId: String?
    @Published private var threadStates: [String: ThreadUIState] = [:]
}
```

한 thread 상태를 atomic하게 갱신할 수 있다.

#### 5. `internalDateMs`를 bigint로 저장

L242의 `internalDateMs: text("internal_date_ms")`는 정렬/범위 쿼리에 매번
cast가 필요하다. Gmail internalDate은 epoch ms 정수이므로 `bigint`로 저장한다.

#### 6. Cmux seam spike PoC를 step 0으로 추가

L132~140의 권장 경로 vs fallback 결정을 "구현 중에 seam이 넓어지면 fallback"
으로 미뤘다. 코딩 절반쯤 가서 갈아타면 짠 코드 상당 부분을 버려야 한다.

**결정:** rollout step 0으로 짧은 spike commit을 추가한다.

1. cmux의 `PanelContentView.swift`, `Panel.swift`, `Workspace.swift`,
   `PanelType` enum을 열어 권장 경로(panel factory seam) 최소 변경 목록을 만든다.
2. 측정값: 건드리는 cmux 파일 수, 신규 public surface 수, 신규 enum case 수.
3. **Threshold 사전 정의:** cmux 파일 3개 이하, 신규 public surface 2개 이하,
   신규 enum case 1개 이하면 권장 경로 lock. 넘으면 fallback (BrowserPanel +
   backend viewer URL)로 lock.
4. spike 코드는 버린다. 측정값과 결정만 본 문서의 "Cmux touchpoints" 섹션에
   업데이트하고 본 구현은 새 branch에서 시작한다.

### 권장 보강 사항 (lock까지는 아니지만 구현 시 반영)

#### 7. `markMissingEmailMessagesDeleted` 호출 시점 명시

L383에 함수만 선언돼 있고 호출 timing이 본문에 없다. cache stale path에서
upsert 직후 `seenGmailMessageIds`로 호출해 Gmail에서 사라진 메시지를 soft
delete 한다고 workflow 흐름(L347~367)에 명시한다.

#### 8. 정렬 키와 표시 키의 관계 명시

L367은 `internalDate` 기준 오름차순 정렬인데 DTO(L162~177)는 `receivedAt`만
노출한다. Date header 위조나 timezone 문제로 둘이 어긋날 수 있으므로 "정렬은
internalDate, 표시는 receivedAt (없으면 internalDate fallback)" 정도로 한 줄
명시한다.

#### 9. `bodyFetchedAt` semantic 명세

`bodyFetchedAt`은 "본문 파싱 시도 시각"으로 정의한다. body가 없거나
attachment-only인 메시지도 row 존재와 `bodyFetchedAt`만으로 "full payload를 한
번 파싱했다"는 신호가 된다.

#### 10. `messageCount` DTO 필드 제거

L162의 `messageCount`는 `messages.length`로 derive 가능하다. 별도 필드는 drift
위험만 더하므로 DTO에서 제거한다.

#### 11. Subject 표시 출처 명시

L234에서 `subject`를 메시지마다 저장한다. Re:/Fwd: prefix 차이가 있을 수 있으니
header subject 표시에는 thread.subject를 쓰고, message card 안에는 message
subject를 쓴다고 view 섹션에 한 줄 추가한다.

### 본 문서와 충돌 시 우선순위

이 "리뷰 피드백" 섹션의 결정이 본문 결정과 충돌하면 이 섹션이 우선한다.
구현자는 본 섹션의 항목 1~6을 lock된 결정으로 취급하고, 7~11은 구현 PR에
반영한다.

## 코덱스 리뷰 피드백 (2026-05-18 append)

PR `phase3-gmail-thread-and-pane-placement` 에 대한 codex 리뷰. 이번 PR 안에서
즉시 처리한 항목과 별도 issue 로 분리한 항목을 구분.

### 이번 PR 에서 fix 한 항목

1. **WKWebView navigation guard**
   - 이전: 모든 http/https/mailto navigation 을 `NSWorkspace.open` 으로 라우팅.
   - 누수: `<meta refresh>` / script-driven navigation 으로 untrusted 이메일이
     사용자 클릭 없이 외부 앱/브라우저를 열 수 있었음.
   - Fix: `webView.url == nil` 인 첫 loadHTMLString 만 허용, 그 후로는
     `navigationAction.navigationType == .linkActivated` 인 사용자 클릭만 open,
     나머지는 모두 cancel.

2. **UserDefaults snapshot cache 보존**
   - 이전: `ZebraGmailAPIClientError.backendUnreachable` catch 에서
     `threads = []` 대입 → `didSet` 으로 빈 배열이 UserDefaults 까지 persist.
     첫 frame UX 목적과 정반대로 cache 가 날아감.
   - Fix: backendUnreachable 분기에서 `threads` 대입 제거. 일시 네트워크 장애
     동안 cached snapshot 그대로 유지, 다음 성공 read 가 자연 replace.

3. **OAuth backfill failure 신호**
   - 이전: `Effect.catchAll` 로 silent swallow → 사용자가 OAuth 직후 빈 inbox
     봐도 원인 모름.
   - Fix: backfill 실패 시 backend `console.warn` 로그 + workflow 응답에
     `backfillSucceeded: boolean` 추가. callback route 가 그 값으로 HTML
     메시지를 분기 ("connected, but initial sync failed. Press the Gmail sync
     button to retry.").

4. **Auth preheat catch log**
   - 이전: `Task.detached { _ = try? await AuthManager.shared.currentTokens() }`
     — throw 시 silent.
   - Fix: `do/catch` 로 변경, 실패 시 NSLog 로 진단 로그 출력. Release 빌드에서도
     남도록 perfLog DEBUG 가드 우회.

### Follow-up issue (별도 PR/issue)

5. **PanelType piggyback 누수**
   - codex 지적: command palette / lifecycle event / search index 에서 email
     panel 이 markdown 으로 보임.
   - 이번 PR 보류 이유: 가드 추가하려면 cmux upstream 4~5 파일 더 건드려야 함.
     piggyback 전체 의도(cmux 최소 침투)와 일관성 어긋남. 정석은 PanelType
     enum 에 `.zebraEmail` case 추가 후 모든 exhaustive switch 처리 — 큰 작업.
   - User-facing 영향: search 분류 라벨 "Markdown", lifecycle event 의 type
     필드. 직접 깨지는 동작 없음.
   - Follow-up: 별도 PR 로 PanelType enum case 도입 또는 helper 함수에 panel
     인스턴스 검사 가드 통합.

6. **history.list incremental sync (label/thread 자동 reconciliation)**
   - 현재 skip-existing-ids 가 label 토글 (STARRED, UNREAD) 을 latest_id
     바뀔 때까지 미반영. Pub/Sub watch + history.list 도입 시 자동 해결.
   - 인프라 비용: Gcp Pub/Sub topic, watch 등록 cron, OIDC 검증.

7. **WKWebView malicious HTML regression samples**
   - sanitize + CSP 정책의 빈틈 검증용 sample HTML 세트 작성. 신규 보안
     fix 시 회귀 방지.

8. **thread missing reconciliation (false soft delete 가드)**
   - `markMissingEmailMessagesDeleted` 가 Gmail 응답 일시 누락을 archive 와
     혼동 가능. 응답 검증 가드 (예: 최소 메시지 수 sanity check) 검토.

9. **본문 평문 DB cache 보안/프라이버시 정책**
   - `email_messages.body_text/body_html` 가 평문 저장. 보안 결정 누락.
   - v1 OK 로 두되 retention policy 명시 필요: TTL (예: 30일 후 본문만 purge),
     Gmail disconnect 시 cascade 삭제 (이미 cascade FK 로 처리됨), 또는
     암호화. 셋 중 하나 follow-up 으로.
