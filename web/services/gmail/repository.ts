import { and, desc, eq, isNull } from "drizzle-orm";
import * as Effect from "effect/Effect";
import { cloudDb } from "../../db/client";
import {
  emailAccounts,
  emailAccountTokens,
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

export function consumeOAuthState(state: string): Effect.Effect<GmailOAuthStateRow | null, GmailDatabaseError> {
  return dbEffect("consume_oauth_state", async () => {
    const db = cloudDb();
    const [row] = await db
      .select()
      .from(gmailOauthStates)
      .where(eq(gmailOauthStates.state, state))
      .limit(1);
    if (!row) return null;
    await db.delete(gmailOauthStates).where(eq(gmailOauthStates.state, state));
    return row;
  });
}

export function upsertEmailAccount(input: {
  readonly userId: string;
  readonly email: string;
  readonly providerAccountId?: string | null;
}): Effect.Effect<EmailAccountRow, GmailDatabaseError> {
  return dbEffect("upsert_email_account", async () => {
    const now = new Date();
    const [row] = await cloudDb()
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
    return row;
  });
}

export function upsertEmailAccountTokens(input: {
  readonly emailAccountId: string;
  readonly accessTokenEncrypted: string;
  readonly refreshTokenEncrypted: string;
  readonly expiresAt: Date;
}): Effect.Effect<void, GmailDatabaseError> {
  return dbEffect("upsert_email_account_tokens", async () => {
    const now = new Date();
    await cloudDb()
      .insert(emailAccountTokens)
      .values({
        emailAccountId: input.emailAccountId,
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

export function upsertEmailThreads(rows: readonly EmailThreadInsert[]): Effect.Effect<number, GmailDatabaseError> {
  return dbEffect("upsert_email_threads", async () => {
    if (rows.length === 0) return 0;
    const now = new Date();
    const db = cloudDb();
    for (const row of rows) {
      await db
        .insert(emailThreads)
        .values({
          ...row,
          createdAt: row.createdAt ?? now,
          updatedAt: now,
          deletedAt: null,
        })
        .onConflictDoUpdate({
          target: [emailThreads.emailAccountId, emailThreads.gmailThreadId],
          set: {
            latestGmailMessageId: row.latestGmailMessageId,
            subject: row.subject,
            snippet: row.snippet ?? null,
            lastSenderName: row.lastSenderName ?? null,
            lastSenderEmail: row.lastSenderEmail ?? null,
            lastMessageAt: row.lastMessageAt,
            messageCount: row.messageCount ?? 1,
            hasAttachment: row.hasAttachment ?? false,
            labelIds: row.labelIds ?? [],
            updatedAt: now,
            deletedAt: null,
          },
        });
    }
    return rows.length;
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
