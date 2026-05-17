import { randomBytes } from "node:crypto";
import * as Effect from "effect/Effect";
import { decryptGmailToken, encryptGmailToken } from "./crypto";
import {
  createGmailAuthUrl,
  createPkcePair,
  exchangeGmailCode,
  fetchGmailMessage,
  fetchGmailProfile,
  gmailOAuthConfig,
  listRecentInboxMessages,
  parseGmailMessage,
  refreshGmailAccessToken,
  type ParsedGmailMessage,
} from "./google";
import {
  GmailAuthError,
  GmailConfigError,
  GmailDatabaseError,
  GmailNotConnectedError,
  GmailProviderError,
} from "./errors";
import {
  consumeOAuthState,
  getConnectedEmailAccount,
  listEmailThreads,
  saveOAuthState,
  updateAccessToken,
  updateSyncState,
  upsertEmailAccount,
  upsertEmailAccountTokens,
  upsertEmailThreads,
  type ConnectedEmailAccount,
  type EmailThreadInsert,
  type EmailThreadRow,
} from "./repository";

export type GmailOAuthStart = {
  readonly authUrl: string;
};

export type GmailOAuthCallbackResult = {
  readonly email: string;
  readonly syncedThreads: number;
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

export function runGmailWorkflow<A, E>(effect: Effect.Effect<A, E>): Promise<A> {
  return Effect.runPromise(effect);
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
      expiresAt: new Date(Date.now() + 10 * 60 * 1000),
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
  GmailAuthError | GmailConfigError | GmailDatabaseError | GmailNotConnectedError | GmailProviderError
> {
  return Effect.gen(function* () {
    const storedState = yield* consumeOAuthState(input.state);
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
    const account = yield* upsertEmailAccount({
      userId: storedState.userId,
      email: profile.emailAddress,
      providerAccountId: profile.emailAddress,
    });
    const accessTokenEncrypted = yield* syncConfig(() => encryptGmailToken(token.accessToken));
    const refreshTokenEncrypted = yield* syncConfig(() => encryptGmailToken(token.refreshToken));
    yield* upsertEmailAccountTokens({
      emailAccountId: account.id,
      accessTokenEncrypted,
      refreshTokenEncrypted,
      expiresAt: token.expiresAt,
    });
    yield* updateSyncState({
      emailAccountId: account.id,
      lastSyncCursor: profile.historyId ?? null,
      lastSyncedAt: new Date(),
    });
    const sync = yield* syncRecentGmail({ userId: storedState.userId, request: input.request });
    return {
      email: profile.emailAddress,
      syncedThreads: sync.upserted,
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
    const rows = yield* listEmailThreads({ userId, limit: 100 });
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
    const listed = yield* providerEffect("list_messages", () => listRecentInboxMessages(accessToken, 50));
    const messages = yield* providerEffect("get_messages", async () => {
      const fetched = await Promise.all(listed.map((message) => fetchGmailMessage(accessToken, message.id)));
      return fetched.map(parseGmailMessage);
    });
    const rows = threadRows({
      userId: input.userId,
      emailAccountId: connection.account.id,
      messages,
    });
    const upserted = yield* upsertEmailThreads(rows);
    yield* updateSyncState({
      emailAccountId: connection.account.id,
      lastSyncCursor: latestHistoryId(messages),
      lastSyncedAt: new Date(),
    });
    return { upserted };
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
    if (token.expiresAt.getTime() > Date.now() + 60 * 1000) {
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

function latestHistoryId(messages: readonly ParsedGmailMessage[]): string | null {
  const sorted = messages
    .map((message) => message.historyId)
    .filter((value): value is string => !!value)
    .sort((a, b) => {
      try {
        const left = BigInt(a);
        const right = BigInt(b);
        if (left === right) return 0;
        return left > right ? -1 : 1;
      } catch {
        return b.localeCompare(a);
      }
    });
  return sorted[0] ?? null;
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
