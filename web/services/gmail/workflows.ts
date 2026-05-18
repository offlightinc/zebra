import { randomBytes } from "node:crypto";
import * as Effect from "effect/Effect";
import { decryptGmailToken, encryptGmailToken } from "./crypto";
import {
  createGmailAuthUrl,
  createPkcePair,
  exchangeGmailCode,
  fetchGmailMessage,
  fetchGmailProfile,
  fetchGmailThread,
  gmailOAuthConfig,
  listRecentInboxMessages,
  parseGmailMessage,
  parseGmailThreadMessages,
  refreshGmailAccessToken,
  type ParsedGmailMessage,
  type ParsedGmailThreadMessage,
} from "./google";
import {
  GmailAuthError,
  GmailConfigError,
  GmailDatabaseError,
  GmailNotConnectedError,
  GmailProviderError,
  gmailWorkflowErrorCause,
} from "./errors";
import {
  connectGmailAccount,
  getConnectedEmailAccount,
  listEmailMessagesForThread,
  listEmailThreads,
  listExistingLatestMessageIds,
  loadOAuthState,
  loadEmailThreadByGmailThreadId,
  markMissingEmailMessagesDeleted,
  saveOAuthState,
  updateAccessToken,
  updateSyncState,
  upsertEmailMessages,
  upsertEmailThreads,
  type ConnectedEmailAccount,
  type EmailMessageInsert,
  type EmailMessageRow,
  type EmailThreadInsert,
  type EmailThreadRow,
} from "./repository";

const oauthStateTTLMs = 10 * 60 * 1000;
const emailThreadListLimit = 100;
const recentInboxMessageLimit = 50;
const tokenRefreshLeewayMs = 60 * 1000;

export type GmailOAuthStart = {
  readonly authUrl: string;
};

export type GmailOAuthCallbackResult = {
  readonly email: string;
  /**
   * true 면 OAuth 콜백 안에서 inbox backfill 까지 성공.
   * false 면 OAuth 자체는 성공(토큰 저장됨)했지만 첫 inbox sync 가 실패.
   * 호출자(callback route 등)는 사용자에게 "연결됐지만 동기화 실패 → 새로고침 눌러주세요" 안내 가능.
   */
  readonly backfillSucceeded: boolean;
};

export type GmailStatus = {
  readonly connected: boolean;
  readonly email: string | null;
  readonly lastSyncedAt: string | null;
};

export type GmailThreadDTO = {
  readonly id: string;
  readonly subject: string;
  readonly senderName: string;
  readonly receivedAt: string;
  readonly unread: boolean;
  readonly starred: boolean;
  readonly hasAttachment: boolean;
  readonly labelIds: readonly string[];
  readonly category: "primary" | "updates" | "promotions" | "social" | "forums" | "purchases" | null;
};

export type GmailThreadMessagesResponse = {
  readonly threadId: string;
  readonly cached: boolean;
  readonly messages: readonly GmailThreadMessageDTO[];
};

export type GmailThreadMessageDTO = {
  readonly messageId: string;
  readonly threadId: string;
  readonly internetMessageId: string | null;
  readonly subject: string | null;
  readonly fromName: string | null;
  readonly fromEmail: string | null;
  readonly to: string | null;
  readonly cc: string | null;
  readonly receivedAt: string | null;
  readonly snippet: string | null;
  readonly labelIds: readonly string[];
  readonly isUnread: boolean;
  readonly isSent: boolean;
  readonly hasAttachment: boolean;
  readonly bodyText: string | null;
  readonly bodyHtml: string | null;
};

export function runGmailWorkflow<A, E>(effect: Effect.Effect<A, E>): Promise<A> {
  return Effect.runPromise(effect).catch((err) => {
    throw gmailWorkflowErrorCause(err) ?? err;
  });
}

export function startGmailOAuth(input: {
  readonly userId: string;
  readonly request: Request;
}): Effect.Effect<GmailOAuthStart, GmailConfigError | GmailDatabaseError> {
  return Effect.gen(function* () {
    const config = yield* syncConfig(() => gmailOAuthConfig(input.request));
    const pkce = createPkcePair();
    const state = randomBytes(32).toString("base64url");
    yield* saveOAuthState({
      state,
      userId: input.userId,
      codeVerifier: pkce.codeVerifier,
      expiresAt: new Date(Date.now() + oauthStateTTLMs),
    });
    return {
      authUrl: createGmailAuthUrl({
        config,
        state,
        codeChallenge: pkce.codeChallenge,
      }),
    };
  });
}

export function handleGmailOAuthCallback(input: {
  readonly code: string;
  readonly state: string;
  readonly request: Request;
}): Effect.Effect<
  GmailOAuthCallbackResult,
  GmailAuthError | GmailConfigError | GmailDatabaseError | GmailProviderError
> {
  return Effect.gen(function* () {
    const storedState = yield* loadOAuthState(input.state);
    if (!storedState) {
      return yield* Effect.fail(new GmailAuthError("Gmail OAuth state was not found or was already used."));
    }
    if (storedState.expiresAt.getTime() < Date.now()) {
      return yield* Effect.fail(new GmailAuthError("Gmail OAuth state has expired."));
    }
    const config = yield* syncConfig(() => gmailOAuthConfig(input.request));
    const token = yield* providerEffect("oauth_exchange", () => exchangeGmailCode({
      config,
      code: input.code,
      codeVerifier: storedState.codeVerifier,
    }));
    const profile = yield* providerEffect("profile", () => fetchGmailProfile(token.accessToken));
    const accessTokenEncrypted = yield* syncConfig(() => encryptGmailToken(token.accessToken));
    const refreshTokenEncrypted = yield* syncConfig(() => encryptGmailToken(token.refreshToken));
    yield* connectGmailAccount({
      state: input.state,
      userId: storedState.userId,
      email: profile.emailAddress,
      providerAccountId: profile.emailAddress,
      accessTokenEncrypted,
      refreshTokenEncrypted,
      expiresAt: token.expiresAt,
      lastSyncCursor: profile.historyId ?? null,
    });
    // Backfill recent inbox so the first sidebar view has threads to show.
    // Best-effort: a transient Gmail failure here shouldn't block the OAuth
    // result (account+token are already persisted), but we surface it on the
    // callback HTML so the user knows to press the sync button afterwards.
    // Backend log here also lets us correlate post-launch empty inbox reports
    // with the original sync failure.
    const backfillSucceeded = yield* Effect.catchAll(
      syncRecentGmail({ userId: storedState.userId, request: input.request }).pipe(
        Effect.map(() => true),
      ),
      (error) => Effect.sync(() => {
        const message = error instanceof Error ? error.message : String(error);
        console.warn(
          `[gmail.oauth.backfill_failed] userId=${storedState.userId} email=${profile.emailAddress} error=${message}`,
        );
        return false;
      }),
    );
    return {
      email: profile.emailAddress,
      backfillSucceeded,
    };
  });
}

export function getGmailStatus(userId: string): Effect.Effect<GmailStatus, GmailDatabaseError> {
  return Effect.gen(function* () {
    const connection = yield* getConnectedEmailAccount(userId);
    if (!connection) {
      return { connected: false, email: null, lastSyncedAt: null };
    }
    return {
      connected: true,
      email: connection.account.email,
      lastSyncedAt: connection.syncState?.lastSyncedAt?.toISOString() ?? null,
    };
  });
}

export function listGmailThreadDTOs(userId: string): Effect.Effect<readonly GmailThreadDTO[], GmailDatabaseError> {
  return Effect.gen(function* () {
    const rows = yield* listEmailThreads({ userId, limit: emailThreadListLimit });
    return rows.map(threadDTO);
  });
}

export function syncRecentGmail(input: {
  readonly userId: string;
  readonly request: Request;
}): Effect.Effect<
  { readonly upserted: number },
  GmailConfigError | GmailDatabaseError | GmailNotConnectedError | GmailProviderError
> {
  return Effect.gen(function* () {
    const connection = yield* getConnectedEmailAccount(input.userId);
    if (!connection?.token) {
      return yield* Effect.fail(new GmailNotConnectedError());
    }
    const config = yield* syncConfig(() => gmailOAuthConfig(input.request));
    const accessToken = yield* validAccessToken({ connection, config });
    const listed = yield* providerEffect("list_messages", () => listRecentInboxMessages(accessToken, recentInboxMessageLimit));
    // Skip messages whose id already matches some thread's latest message id —
    // those threads are unchanged since last sync, so re-fetching their
    // metadata wastes Gmail quota and adds latency.
    const knownLatestIds = yield* listExistingLatestMessageIds({
      emailAccountId: connection.account.id,
      gmailMessageIds: listed.map((message) => message.id),
    });
    const toFetch = listed.filter((message) => !knownLatestIds.has(message.id));
    const messages = yield* providerEffect("get_messages", async () => {
      if (toFetch.length === 0) return [];
      const fetched = await Promise.all(toFetch.map((message) => fetchGmailMessage(accessToken, message.id)));
      return fetched.map(parseGmailMessage);
    });
    let upserted = 0;
    if (messages.length > 0) {
      const rows = threadRows({
        userId: input.userId,
        emailAccountId: connection.account.id,
        messages,
      });
      upserted = yield* upsertEmailThreads(rows);
    }
    const profile = yield* providerEffect("profile", () => fetchGmailProfile(accessToken));
    yield* updateSyncState({
      emailAccountId: connection.account.id,
      lastSyncCursor: profile.historyId ?? connection.syncState?.lastSyncCursor ?? null,
      lastSyncedAt: new Date(),
    });
    return { upserted };
  });
}

export function getGmailThreadMessages(input: {
  readonly userId: string;
  readonly request: Request;
  readonly threadId: string;
  readonly forceRefresh?: boolean;
}): Effect.Effect<
  GmailThreadMessagesResponse,
  GmailConfigError | GmailDatabaseError | GmailNotConnectedError | GmailProviderError
> {
  return Effect.gen(function* () {
    const connection = yield* getConnectedEmailAccount(input.userId);
    if (!connection?.token) {
      return yield* Effect.fail(new GmailNotConnectedError());
    }
    const config = yield* syncConfig(() => gmailOAuthConfig(input.request));
    const accessToken = yield* validAccessToken({ connection, config });
    let threadRow = yield* loadEmailThreadByGmailThreadId({
      userId: input.userId,
      emailAccountId: connection.account.id,
      gmailThreadId: input.threadId,
    });

    if (threadRow) {
      const cachedMessages = yield* listEmailMessagesForThread({
        userId: input.userId,
        emailThreadId: threadRow.id,
      });
      if (!input.forceRefresh && isMessageCacheFresh(threadRow, cachedMessages)) {
        return threadMessagesResponse(input.threadId, true, cachedMessages);
      }
    }

    const gmailThread = yield* providerEffect("get_thread", () => fetchGmailThread(accessToken, input.threadId));
    const parsedMessages = [...parseGmailThreadMessages(gmailThread)]
      .sort(compareParsedThreadMessages);
    if (!threadRow) {
      const threadUpserts = threadRowsFromThreadMessages({
        userId: input.userId,
        emailAccountId: connection.account.id,
        messages: parsedMessages,
      });
      yield* upsertEmailThreads(threadUpserts);
      threadRow = yield* loadEmailThreadByGmailThreadId({
        userId: input.userId,
        emailAccountId: connection.account.id,
        gmailThreadId: input.threadId,
      });
    }
    if (!threadRow) {
      return {
        threadId: input.threadId,
        cached: false,
        messages: [],
      };
    }

    yield* upsertEmailMessages(emailMessageRows({
      userId: input.userId,
      emailAccountId: connection.account.id,
      emailThreadId: threadRow.id,
      gmailThreadId: input.threadId,
      messages: parsedMessages,
    }));
    yield* markMissingEmailMessagesDeleted({
      emailThreadId: threadRow.id,
      seenGmailMessageIds: parsedMessages.map((message) => message.messageId),
    });
    const savedMessages = yield* listEmailMessagesForThread({
      userId: input.userId,
      emailThreadId: threadRow.id,
    });
    return threadMessagesResponse(input.threadId, false, savedMessages);
  });
}

function validAccessToken(input: {
  readonly connection: ConnectedEmailAccount;
  readonly config: ReturnType<typeof gmailOAuthConfig>;
}): Effect.Effect<string, GmailConfigError | GmailDatabaseError | GmailNotConnectedError | GmailProviderError> {
  return Effect.gen(function* () {
    const token = input.connection.token;
    if (!token) {
      return yield* Effect.fail(new GmailNotConnectedError());
    }
    if (token.expiresAt.getTime() > Date.now() + tokenRefreshLeewayMs) {
      return yield* syncConfig(() => decryptGmailToken(token.accessTokenEncrypted));
    }
    const refreshToken = yield* syncConfig(() => decryptGmailToken(token.refreshTokenEncrypted));
    const refreshed = yield* providerEffect("oauth_refresh", () => refreshGmailAccessToken({
      config: input.config,
      refreshToken,
    }));
    const refreshedAccessTokenEncrypted = yield* syncConfig(() => encryptGmailToken(refreshed.accessToken));
    yield* updateAccessToken({
      emailAccountId: input.connection.account.id,
      accessTokenEncrypted: refreshedAccessTokenEncrypted,
      expiresAt: refreshed.expiresAt,
    });
    return refreshed.accessToken;
  });
}

function isMessageCacheFresh(
  thread: EmailThreadRow,
  messages: readonly EmailMessageRow[],
): boolean {
  if (messages.length === 0) return false;
  if (!messages.some((message) => message.gmailMessageId === thread.latestGmailMessageId)) {
    return false;
  }
  return true;
}

function threadRows(input: {
  readonly userId: string;
  readonly emailAccountId: string;
  readonly messages: readonly ParsedGmailMessage[];
}): readonly EmailThreadInsert[] {
  const byThread = new Map<string, {
    latest: ParsedGmailMessage;
    count: number;
    labels: Set<string>;
    hasAttachment: boolean;
  }>();
  for (const message of input.messages) {
    const existing = byThread.get(message.threadId);
    if (!existing) {
      byThread.set(message.threadId, {
        latest: message,
        count: 1,
        labels: new Set(message.labelIds),
        hasAttachment: message.hasAttachment,
      });
      continue;
    }
    existing.count += 1;
    for (const label of message.labelIds) existing.labels.add(label);
    existing.hasAttachment = existing.hasAttachment || message.hasAttachment;
    if (message.receivedAt.getTime() > existing.latest.receivedAt.getTime()) {
      existing.latest = message;
    }
  }
  return [...byThread.entries()].map(([gmailThreadId, thread]) => ({
    userId: input.userId,
    emailAccountId: input.emailAccountId,
    gmailThreadId,
    latestGmailMessageId: thread.latest.messageId,
    subject: thread.latest.subject,
    snippet: thread.latest.snippet,
    lastSenderName: thread.latest.senderName,
    lastSenderEmail: thread.latest.senderEmail,
    lastMessageAt: thread.latest.receivedAt,
    messageCount: thread.count,
    hasAttachment: thread.hasAttachment,
    labelIds: [...thread.labels],
  }));
}

function threadRowsFromThreadMessages(input: {
  readonly userId: string;
  readonly emailAccountId: string;
  readonly messages: readonly ParsedGmailThreadMessage[];
}): readonly EmailThreadInsert[] {
  const byThread = new Map<string, {
    latest: ParsedGmailThreadMessage;
    count: number;
    labels: Set<string>;
    hasAttachment: boolean;
  }>();
  for (const message of input.messages) {
    const existing = byThread.get(message.threadId);
    if (!existing) {
      byThread.set(message.threadId, {
        latest: message,
        count: 1,
        labels: new Set(message.labelIds),
        hasAttachment: message.hasAttachment,
      });
      continue;
    }
    existing.count += 1;
    for (const label of message.labelIds) existing.labels.add(label);
    existing.hasAttachment = existing.hasAttachment || message.hasAttachment;
    if (parsedThreadMessageTime(message) > parsedThreadMessageTime(existing.latest)) {
      existing.latest = message;
    }
  }
  return [...byThread.entries()].map(([gmailThreadId, thread]) => ({
    userId: input.userId,
    emailAccountId: input.emailAccountId,
    gmailThreadId,
    latestGmailMessageId: thread.latest.messageId,
    subject: thread.latest.subject ?? "(no subject)",
    snippet: thread.latest.snippet,
    lastSenderName: thread.latest.senderName ?? thread.latest.senderEmail,
    lastSenderEmail: thread.latest.senderEmail,
    lastMessageAt: thread.latest.receivedAt ?? new Date(),
    messageCount: thread.count,
    hasAttachment: thread.hasAttachment,
    labelIds: [...thread.labels],
  }));
}

function emailMessageRows(input: {
  readonly userId: string;
  readonly emailAccountId: string;
  readonly emailThreadId: string;
  readonly gmailThreadId: string;
  readonly messages: readonly ParsedGmailThreadMessage[];
}): readonly EmailMessageInsert[] {
  const now = new Date();
  return input.messages.map((message) => ({
    userId: input.userId,
    emailAccountId: input.emailAccountId,
    emailThreadId: input.emailThreadId,
    gmailThreadId: input.gmailThreadId,
    gmailMessageId: message.messageId,
    internetMessageId: message.internetMessageId,
    subject: message.subject,
    snippet: message.snippet,
    fromName: message.senderName,
    fromEmail: message.senderEmail,
    toRecipients: message.to,
    ccRecipients: message.cc,
    receivedAt: message.receivedAt,
    internalDateMs: message.internalDateMs,
    isUnread: message.isUnread,
    isSent: message.isSent,
    hasAttachment: message.hasAttachment,
    labelIds: [...message.labelIds],
    bodyText: message.bodyText,
    bodyHtml: message.bodyHtml,
    bodyFetchedAt: now,
  }));
}

function threadMessagesResponse(
  threadId: string,
  cached: boolean,
  rows: readonly EmailMessageRow[],
): GmailThreadMessagesResponse {
  return {
    threadId,
    cached,
    messages: rows.map(emailMessageDTO),
  };
}

function emailMessageDTO(row: EmailMessageRow): GmailThreadMessageDTO {
  const labels = Array.isArray(row.labelIds) ? row.labelIds : [];
  return {
    messageId: row.gmailMessageId,
    threadId: row.gmailThreadId,
    internetMessageId: row.internetMessageId,
    subject: row.subject,
    fromName: row.fromName,
    fromEmail: row.fromEmail,
    to: row.toRecipients,
    cc: row.ccRecipients,
    receivedAt: row.receivedAt?.toISOString() ?? null,
    snippet: row.snippet,
    labelIds: labels,
    isUnread: row.isUnread,
    isSent: row.isSent,
    hasAttachment: row.hasAttachment,
    bodyText: row.bodyText,
    bodyHtml: row.bodyHtml,
  };
}

function compareParsedThreadMessages(
  left: ParsedGmailThreadMessage,
  right: ParsedGmailThreadMessage,
): number {
  const byTime = parsedThreadMessageTime(left) - parsedThreadMessageTime(right);
  if (byTime !== 0) return byTime;
  return left.messageId.localeCompare(right.messageId);
}

function parsedThreadMessageTime(message: ParsedGmailThreadMessage): number {
  if (message.internalDateMs !== null) return message.internalDateMs;
  return message.receivedAt?.getTime() ?? 0;
}

function threadDTO(row: EmailThreadRow): GmailThreadDTO {
  const labels = Array.isArray(row.labelIds) ? row.labelIds : [];
  return {
    id: row.gmailThreadId,
    subject: row.subject,
    senderName: row.lastSenderName ?? row.lastSenderEmail ?? "",
    receivedAt: row.lastMessageAt.toISOString(),
    unread: labels.includes("UNREAD"),
    starred: labels.includes("STARRED"),
    hasAttachment: row.hasAttachment,
    labelIds: labels,
    category: categoryFromLabels(labels),
  };
}

function categoryFromLabels(labels: readonly string[]): GmailThreadDTO["category"] {
  if (labels.includes("CATEGORY_UPDATES")) return "updates";
  if (labels.includes("CATEGORY_PROMOTIONS")) return "promotions";
  if (labels.includes("CATEGORY_SOCIAL")) return "social";
  if (labels.includes("CATEGORY_FORUMS")) return "forums";
  if (labels.includes("CATEGORY_PURCHASES")) return "purchases";
  if (labels.includes("INBOX")) return "primary";
  return null;
}

function providerEffect<A>(
  operation: string,
  run: () => Promise<A>,
): Effect.Effect<A, GmailProviderError> {
  return Effect.tryPromise({
    try: run,
    catch: (cause) => cause instanceof GmailProviderError
      ? cause
      : new GmailProviderError({ operation, message: "Google Gmail request failed.", cause }),
  });
}

function syncConfig<A>(run: () => A): Effect.Effect<A, GmailConfigError> {
  return Effect.try({
    try: run,
    catch: (cause) => cause instanceof GmailConfigError
      ? cause
      : new GmailConfigError("Gmail configuration is invalid."),
  });
}
