import { and, asc, desc, eq, inArray, isNull, notInArray, sql } from "drizzle-orm";
import * as Effect from "effect/Effect";
import { cloudDb } from "../../db/client";
import {
  emailAccounts,
  emailAccountTokens,
  emailMessages,
  emailSyncState,
  emailThreads,
  gmailOauthStates,
} from "../../db/schema";
import { GmailDatabaseError } from "./errors";

export type GmailOAuthStateRow = typeof gmailOauthStates.$inferSelect;
export type EmailAccountRow = typeof emailAccounts.$inferSelect;
export type EmailAccountTokenRow = typeof emailAccountTokens.$inferSelect;
export type EmailThreadRow = typeof emailThreads.$inferSelect;
export type EmailThreadInsert = typeof emailThreads.$inferInsert;
export type EmailMessageRow = typeof emailMessages.$inferSelect;
export type EmailMessageInsert = typeof emailMessages.$inferInsert;
export type EmailSyncStateRow = typeof emailSyncState.$inferSelect;

export type ConnectedEmailAccount = {
  readonly account: EmailAccountRow;
  readonly token: EmailAccountTokenRow | null;
  readonly syncState: EmailSyncStateRow | null;
};

function dbEffect<A>(
  operation: string,
  run: () => Promise<A>,
): Effect.Effect<A, GmailDatabaseError> {
  return Effect.tryPromise({
    try: run,
    catch: (cause) => new GmailDatabaseError({ operation, cause }),
  });
}

export function saveOAuthState(input: {
  readonly state: string;
  readonly userId: string;
  readonly codeVerifier: string;
  readonly expiresAt: Date;
}): Effect.Effect<void, GmailDatabaseError> {
  return dbEffect("save_oauth_state", async () => {
    const now = new Date();
    await cloudDb()
      .insert(gmailOauthStates)
      .values({ ...input, createdAt: now })
      .onConflictDoUpdate({
        target: gmailOauthStates.state,
        set: {
          userId: input.userId,
          codeVerifier: input.codeVerifier,
          expiresAt: input.expiresAt,
          createdAt: now,
        },
      });
  });
}

export function loadOAuthState(state: string): Effect.Effect<GmailOAuthStateRow | null, GmailDatabaseError> {
  return dbEffect("load_oauth_state", async () => {
    const [row] = await cloudDb()
      .select()
      .from(gmailOauthStates)
      .where(eq(gmailOauthStates.state, state))
      .limit(1);
    return row ?? null;
  });
}

export function connectGmailAccount(input: {
  readonly state: string;
  readonly userId: string;
  readonly email: string;
  readonly providerAccountId?: string | null;
  readonly accessTokenEncrypted: string;
  readonly refreshTokenEncrypted: string;
  readonly expiresAt: Date;
  readonly lastSyncCursor?: string | null;
}): Effect.Effect<EmailAccountRow, GmailDatabaseError> {
  return dbEffect("connect_gmail_account", async () => {
    const now = new Date();
    return await cloudDb().transaction(async (tx) => {
      const [account] = await tx
        .insert(emailAccounts)
        .values({
          userId: input.userId,
          provider: "gmail",
          email: input.email,
          providerAccountId: input.providerAccountId ?? input.email,
          connectedAt: now,
          disconnectedAt: null,
          createdAt: now,
          updatedAt: now,
        })
        .onConflictDoUpdate({
          target: [emailAccounts.userId, emailAccounts.provider],
          set: {
            email: input.email,
            providerAccountId: input.providerAccountId ?? input.email,
            connectedAt: now,
            disconnectedAt: null,
            updatedAt: now,
          },
        })
        .returning();

      await tx
        .insert(emailAccountTokens)
        .values({
          emailAccountId: account.id,
          accessTokenEncrypted: input.accessTokenEncrypted,
          refreshTokenEncrypted: input.refreshTokenEncrypted,
          expiresAt: input.expiresAt,
          createdAt: now,
          updatedAt: now,
        })
        .onConflictDoUpdate({
          target: emailAccountTokens.emailAccountId,
          set: {
            accessTokenEncrypted: input.accessTokenEncrypted,
            refreshTokenEncrypted: input.refreshTokenEncrypted,
            expiresAt: input.expiresAt,
            updatedAt: now,
          },
        });

      await tx
        .insert(emailSyncState)
        .values({
          emailAccountId: account.id,
          lastSyncCursor: input.lastSyncCursor ?? null,
          lastSyncedAt: null,
          createdAt: now,
          updatedAt: now,
        })
        .onConflictDoUpdate({
          target: emailSyncState.emailAccountId,
          set: {
            lastSyncCursor: input.lastSyncCursor ?? null,
            updatedAt: now,
          },
        });

      await tx.delete(gmailOauthStates).where(eq(gmailOauthStates.state, input.state));

      return account;
    });
  });
}

export function updateAccessToken(input: {
  readonly emailAccountId: string;
  readonly accessTokenEncrypted: string;
  readonly expiresAt: Date;
}): Effect.Effect<void, GmailDatabaseError> {
  return dbEffect("update_access_token", async () => {
    await cloudDb()
      .update(emailAccountTokens)
      .set({
        accessTokenEncrypted: input.accessTokenEncrypted,
        expiresAt: input.expiresAt,
        updatedAt: new Date(),
      })
      .where(eq(emailAccountTokens.emailAccountId, input.emailAccountId));
  });
}

export function getConnectedEmailAccount(userId: string): Effect.Effect<ConnectedEmailAccount | null, GmailDatabaseError> {
  return dbEffect("get_connected_email_account", async () => {
    const db = cloudDb();
    const [account] = await db
      .select()
      .from(emailAccounts)
      .where(and(
        eq(emailAccounts.userId, userId),
        eq(emailAccounts.provider, "gmail"),
        isNull(emailAccounts.disconnectedAt),
      ))
      .limit(1);
    if (!account) return null;
    const [token] = await db
      .select()
      .from(emailAccountTokens)
      .where(eq(emailAccountTokens.emailAccountId, account.id))
      .limit(1);
    const [syncState] = await db
      .select()
      .from(emailSyncState)
      .where(eq(emailSyncState.emailAccountId, account.id))
      .limit(1);
    return { account, token: token ?? null, syncState: syncState ?? null };
  });
}

export function listEmailThreads(input: {
  readonly userId: string;
  readonly limit: number;
}): Effect.Effect<EmailThreadRow[], GmailDatabaseError> {
  return dbEffect("list_email_threads", async () => {
    return await cloudDb()
      .select()
      .from(emailThreads)
      .where(and(
        eq(emailThreads.userId, input.userId),
        isNull(emailThreads.deletedAt),
      ))
      .orderBy(desc(emailThreads.lastMessageAt))
      .limit(input.limit);
  });
}

export function loadEmailThreadByGmailThreadId(input: {
  readonly userId: string;
  readonly emailAccountId: string;
  readonly gmailThreadId: string;
}): Effect.Effect<EmailThreadRow | null, GmailDatabaseError> {
  return dbEffect("load_email_thread_by_gmail_thread_id", async () => {
    const [row] = await cloudDb()
      .select()
      .from(emailThreads)
      .where(and(
        eq(emailThreads.userId, input.userId),
        eq(emailThreads.emailAccountId, input.emailAccountId),
        eq(emailThreads.gmailThreadId, input.gmailThreadId),
        isNull(emailThreads.deletedAt),
      ))
      .limit(1);
    return row ?? null;
  });
}

export function listExistingLatestMessageIds(input: {
  readonly emailAccountId: string;
  readonly gmailMessageIds: readonly string[];
}): Effect.Effect<ReadonlySet<string>, GmailDatabaseError> {
  return dbEffect("list_existing_latest_message_ids", async () => {
    if (input.gmailMessageIds.length === 0) return new Set<string>();
    const rows = await cloudDb()
      .select({ latestGmailMessageId: emailThreads.latestGmailMessageId })
      .from(emailThreads)
      .where(and(
        eq(emailThreads.emailAccountId, input.emailAccountId),
        inArray(emailThreads.latestGmailMessageId, [...input.gmailMessageIds]),
        isNull(emailThreads.deletedAt),
      ));
    return new Set(rows.map((row) => row.latestGmailMessageId));
  });
}

export function upsertEmailThreads(rows: readonly EmailThreadInsert[]): Effect.Effect<number, GmailDatabaseError> {
  return dbEffect("upsert_email_threads", async () => {
    if (rows.length === 0) return 0;
    const now = new Date();
    await cloudDb().transaction(async (tx) => {
      await tx
        .insert(emailThreads)
        .values(rows.map((row) => ({
          ...row,
          createdAt: row.createdAt ?? now,
          updatedAt: now,
          deletedAt: null,
        })))
        .onConflictDoUpdate({
          target: [emailThreads.emailAccountId, emailThreads.gmailThreadId],
          set: {
            latestGmailMessageId: sql`excluded.latest_gmail_message_id`,
            subject: sql`excluded.subject`,
            snippet: sql`excluded.snippet`,
            lastSenderName: sql`excluded.last_sender_name`,
            lastSenderEmail: sql`excluded.last_sender_email`,
            lastMessageAt: sql`excluded.last_message_at`,
            messageCount: sql`excluded.message_count`,
            hasAttachment: sql`excluded.has_attachment`,
            labelIds: sql`excluded.label_ids`,
            updatedAt: now,
            deletedAt: null,
          },
        });
    });
    return rows.length;
  });
}

export function listEmailMessagesForThread(input: {
  readonly userId: string;
  readonly emailThreadId: string;
}): Effect.Effect<EmailMessageRow[], GmailDatabaseError> {
  return dbEffect("list_email_messages_for_thread", async () => {
    return await cloudDb()
      .select()
      .from(emailMessages)
      .where(and(
        eq(emailMessages.userId, input.userId),
        eq(emailMessages.emailThreadId, input.emailThreadId),
        isNull(emailMessages.deletedAt),
      ))
      .orderBy(asc(emailMessages.receivedAt), asc(emailMessages.gmailMessageId));
  });
}

export function upsertEmailMessages(rows: readonly EmailMessageInsert[]): Effect.Effect<number, GmailDatabaseError> {
  return dbEffect("upsert_email_messages", async () => {
    if (rows.length === 0) return 0;
    const now = new Date();
    await cloudDb().transaction(async (tx) => {
      await tx
        .insert(emailMessages)
        .values(rows.map((row) => ({
          ...row,
          createdAt: row.createdAt ?? now,
          updatedAt: now,
          bodyFetchedAt: row.bodyFetchedAt ?? now,
          deletedAt: null,
        })))
        .onConflictDoUpdate({
          target: [emailMessages.emailAccountId, emailMessages.gmailMessageId],
          set: {
            emailThreadId: sql`excluded.email_thread_id`,
            gmailThreadId: sql`excluded.gmail_thread_id`,
            internetMessageId: sql`excluded.internet_message_id`,
            subject: sql`excluded.subject`,
            snippet: sql`excluded.snippet`,
            fromName: sql`excluded.from_name`,
            fromEmail: sql`excluded.from_email`,
            toRecipients: sql`excluded.to_recipients`,
            ccRecipients: sql`excluded.cc_recipients`,
            receivedAt: sql`excluded.received_at`,
            internalDateMs: sql`excluded.internal_date_ms`,
            isUnread: sql`excluded.is_unread`,
            isSent: sql`excluded.is_sent`,
            hasAttachment: sql`excluded.has_attachment`,
            labelIds: sql`excluded.label_ids`,
            bodyText: sql`excluded.body_text`,
            bodyHtml: sql`excluded.body_html`,
            bodyFetchedAt: sql`excluded.body_fetched_at`,
            updatedAt: now,
            deletedAt: null,
          },
        });
    });
    return rows.length;
  });
}

export function markMissingEmailMessagesDeleted(input: {
  readonly emailThreadId: string;
  readonly seenGmailMessageIds: readonly string[];
}): Effect.Effect<void, GmailDatabaseError> {
  return dbEffect("mark_missing_email_messages_deleted", async () => {
    if (input.seenGmailMessageIds.length === 0) return;
    await cloudDb()
      .update(emailMessages)
      .set({ deletedAt: new Date(), updatedAt: new Date() })
      .where(and(
        eq(emailMessages.emailThreadId, input.emailThreadId),
        isNull(emailMessages.deletedAt),
        notInArray(emailMessages.gmailMessageId, [...input.seenGmailMessageIds]),
      ));
  });
}

export function updateSyncState(input: {
  readonly emailAccountId: string;
  readonly lastSyncCursor: string | null;
  readonly lastSyncedAt: Date;
}): Effect.Effect<void, GmailDatabaseError> {
  return dbEffect("update_sync_state", async () => {
    const now = new Date();
    await cloudDb()
      .insert(emailSyncState)
      .values({
        emailAccountId: input.emailAccountId,
        lastSyncCursor: input.lastSyncCursor,
        lastSyncedAt: input.lastSyncedAt,
        createdAt: now,
        updatedAt: now,
      })
      .onConflictDoUpdate({
        target: emailSyncState.emailAccountId,
        set: {
          lastSyncCursor: input.lastSyncCursor,
          lastSyncedAt: input.lastSyncedAt,
          updatedAt: now,
        },
      });
  });
}
