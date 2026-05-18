import { sql } from "drizzle-orm";
import {
  bigint,
  boolean,
  index,
  integer,
  jsonb,
  pgEnum,
  pgTable,
  text,
  timestamp,
  uniqueIndex,
  uuid,
} from "drizzle-orm/pg-core";

export const vmProvider = pgEnum("vm_provider", ["e2b", "freestyle"]);

export const vmStatus = pgEnum("vm_status", [
  "provisioning",
  "running",
  "failed",
  "paused",
  "destroyed",
]);

export const vmLeaseKind = pgEnum("vm_lease_kind", ["pty", "rpc", "ssh"]);

export const cloudVms = pgTable(
  "cloud_vms",
  {
    id: uuid("id").defaultRandom().primaryKey(),
    userId: text("user_id").notNull(),
    billingTeamId: text("billing_team_id"),
    billingPlanId: text("billing_plan_id"),
    provider: vmProvider("provider").notNull(),
    providerVmId: text("provider_vm_id"),
    imageId: text("image_id").notNull(),
    imageVersion: text("image_version"),
    status: vmStatus("status").notNull().default("provisioning"),
    idempotencyKey: text("idempotency_key"),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
    destroyedAt: timestamp("destroyed_at", { withTimezone: true }),
    failureCode: text("failure_code"),
    failureMessage: text("failure_message"),
  },
  (table) => [
    index("cloud_vms_user_status_idx").on(table.userId, table.status),
    index("cloud_vms_billing_team_status_idx").on(table.billingTeamId, table.status),
    uniqueIndex("cloud_vms_user_idempotency_key_unique")
      .on(table.userId, table.idempotencyKey)
      .where(sql`${table.idempotencyKey} is not null`),
    uniqueIndex("cloud_vms_provider_vm_id_unique")
      .on(table.provider, table.providerVmId)
      .where(sql`${table.providerVmId} is not null`),
  ],
);

export const cloudVmLeases = pgTable(
  "cloud_vm_leases",
  {
    id: uuid("id").defaultRandom().primaryKey(),
    vmId: uuid("vm_id")
      .notNull()
      .references(() => cloudVms.id, { onDelete: "cascade" }),
    userId: text("user_id").notNull(),
    kind: vmLeaseKind("kind").notNull(),
    tokenHash: text("token_hash").notNull(),
    providerIdentityHandle: text("provider_identity_handle"),
    sessionId: text("session_id"),
    transport: text("transport"),
    metadata: jsonb("metadata").$type<Record<string, unknown>>().notNull().default(sql`'{}'::jsonb`),
    expiresAt: timestamp("expires_at", { withTimezone: true }).notNull(),
    consumedAt: timestamp("consumed_at", { withTimezone: true }),
    revokedAt: timestamp("revoked_at", { withTimezone: true }),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [
    index("cloud_vm_leases_vm_kind_idx").on(table.vmId, table.kind),
    index("cloud_vm_leases_identity_idx").on(table.providerIdentityHandle),
    index("cloud_vm_leases_user_expires_idx").on(table.userId, table.expiresAt),
    uniqueIndex("cloud_vm_leases_token_hash_unique").on(table.tokenHash),
  ],
);

export const cloudVmUsageEvents = pgTable(
  "cloud_vm_usage_events",
  {
    id: uuid("id").defaultRandom().primaryKey(),
    userId: text("user_id").notNull(),
    billingTeamId: text("billing_team_id"),
    billingPlanId: text("billing_plan_id"),
    vmId: uuid("vm_id").references(() => cloudVms.id, { onDelete: "set null" }),
    eventType: text("event_type").notNull(),
    provider: vmProvider("provider"),
    imageId: text("image_id"),
    metadata: jsonb("metadata").$type<Record<string, unknown>>().notNull().default(sql`'{}'::jsonb`),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [
    index("cloud_vm_usage_events_user_created_idx").on(table.userId, table.createdAt),
    index("cloud_vm_usage_events_billing_team_created_idx").on(table.billingTeamId, table.createdAt),
    index("cloud_vm_usage_events_vm_created_idx").on(table.vmId, table.createdAt),
    index("cloud_vm_usage_events_type_created_idx").on(table.eventType, table.createdAt),
  ],
);

export const cloudVmBillingGrants = pgTable(
  "cloud_vm_billing_grants",
  {
    id: uuid("id").defaultRandom().primaryKey(),
    billingCustomerType: text("billing_customer_type").notNull(),
    billingCustomerId: text("billing_customer_id").notNull(),
    billingPlanId: text("billing_plan_id").notNull(),
    itemId: text("item_id").notNull(),
    amount: integer("amount").notNull(),
    reason: text("reason").notNull(),
    appliedAt: timestamp("applied_at", { withTimezone: true }),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [
    index("cloud_vm_billing_grants_customer_created_idx")
      .on(table.billingCustomerType, table.billingCustomerId, table.createdAt),
    uniqueIndex("cloud_vm_billing_grants_customer_item_reason_unique")
      .on(table.billingCustomerType, table.billingCustomerId, table.itemId, table.reason),
  ],
);

export const gmailOauthStates = pgTable(
  "gmail_oauth_states",
  {
    state: text("state").primaryKey(),
    userId: text("user_id").notNull(),
    codeVerifier: text("code_verifier").notNull(),
    expiresAt: timestamp("expires_at", { withTimezone: true }).notNull(),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [
    index("gmail_oauth_states_user_expires_idx").on(table.userId, table.expiresAt),
  ],
);

export const emailAccounts = pgTable(
  "email_accounts",
  {
    id: uuid("id").defaultRandom().primaryKey(),
    userId: text("user_id").notNull(),
    provider: text("provider").notNull().default("gmail"),
    email: text("email").notNull(),
    providerAccountId: text("provider_account_id"),
    connectedAt: timestamp("connected_at", { withTimezone: true }).notNull().defaultNow(),
    disconnectedAt: timestamp("disconnected_at", { withTimezone: true }),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [
    index("email_accounts_user_idx").on(table.userId),
    uniqueIndex("email_accounts_user_provider_unique").on(table.userId, table.provider),
  ],
);

export const emailAccountTokens = pgTable("email_account_tokens", {
  emailAccountId: uuid("email_account_id")
    .primaryKey()
    .references(() => emailAccounts.id, { onDelete: "cascade" }),
  accessTokenEncrypted: text("access_token_encrypted").notNull(),
  refreshTokenEncrypted: text("refresh_token_encrypted").notNull(),
  expiresAt: timestamp("expires_at", { withTimezone: true }).notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
});

export const emailThreads = pgTable(
  "email_threads",
  {
    id: uuid("id").defaultRandom().primaryKey(),
    userId: text("user_id").notNull(),
    emailAccountId: uuid("email_account_id")
      .notNull()
      .references(() => emailAccounts.id, { onDelete: "cascade" }),
    gmailThreadId: text("gmail_thread_id").notNull(),
    latestGmailMessageId: text("latest_gmail_message_id").notNull(),
    subject: text("subject").notNull(),
    snippet: text("snippet"),
    lastSenderName: text("last_sender_name"),
    lastSenderEmail: text("last_sender_email"),
    lastMessageAt: timestamp("last_message_at", { withTimezone: true }).notNull(),
    messageCount: integer("message_count").notNull().default(1),
    hasAttachment: boolean("has_attachment").notNull().default(false),
    labelIds: jsonb("label_ids").$type<string[]>().notNull().default(sql`'[]'::jsonb`),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
    deletedAt: timestamp("deleted_at", { withTimezone: true }),
  },
  (table) => [
    index("email_threads_user_last_message_idx").on(table.userId, table.lastMessageAt),
    index("email_threads_account_last_message_idx").on(table.emailAccountId, table.lastMessageAt),
    uniqueIndex("email_threads_account_gmail_thread_unique").on(table.emailAccountId, table.gmailThreadId),
  ],
);

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
    internalDateMs: bigint("internal_date_ms", { mode: "number" }),
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
    uniqueIndex("email_messages_account_gmail_message_unique").on(table.emailAccountId, table.gmailMessageId),
  ],
);

export const emailSyncState = pgTable("email_sync_state", {
  emailAccountId: uuid("email_account_id")
    .primaryKey()
    .references(() => emailAccounts.id, { onDelete: "cascade" }),
  lastSyncCursor: text("last_sync_cursor"),
  lastSyncedAt: timestamp("last_synced_at", { withTimezone: true }),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
});
