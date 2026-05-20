-- Drop all gmail/email tables. Desktop client now reads/writes a local SQLite
-- cache and hits the Clawvisor brain RPC gateway directly (see
-- Packages/ZebraVault/Sources/ZebraVault/Email/ZebraClawvisorEmailClient.swift).
-- The Next.js backend no longer participates in the email flow, so the
-- previously-created Gmail OAuth + thread/message tables are orphaned.
DROP TABLE IF EXISTS "email_messages" CASCADE;
--> statement-breakpoint
DROP TABLE IF EXISTS "email_sync_state" CASCADE;
--> statement-breakpoint
DROP TABLE IF EXISTS "email_account_tokens" CASCADE;
--> statement-breakpoint
DROP TABLE IF EXISTS "email_threads" CASCADE;
--> statement-breakpoint
DROP TABLE IF EXISTS "email_accounts" CASCADE;
--> statement-breakpoint
DROP TABLE IF EXISTS "gmail_oauth_states" CASCADE;
