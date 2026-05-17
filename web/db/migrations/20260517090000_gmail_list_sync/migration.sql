CREATE TABLE "gmail_oauth_states" (
	"state" text PRIMARY KEY NOT NULL,
	"user_id" text NOT NULL,
	"code_verifier" text NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "email_accounts" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
	"user_id" text NOT NULL,
	"provider" text DEFAULT 'gmail' NOT NULL,
	"email" text NOT NULL,
	"provider_account_id" text,
	"connected_at" timestamp with time zone DEFAULT now() NOT NULL,
	"disconnected_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "email_account_tokens" (
	"email_account_id" uuid PRIMARY KEY NOT NULL,
	"access_token_encrypted" text NOT NULL,
	"refresh_token_encrypted" text NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "email_threads" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
	"user_id" text NOT NULL,
	"email_account_id" uuid NOT NULL,
	"gmail_thread_id" text NOT NULL,
	"latest_gmail_message_id" text NOT NULL,
	"subject" text NOT NULL,
	"snippet" text,
	"last_sender_name" text,
	"last_sender_email" text,
	"last_message_at" timestamp with time zone NOT NULL,
	"message_count" integer DEFAULT 1 NOT NULL,
	"has_attachment" boolean DEFAULT false NOT NULL,
	"label_ids" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"deleted_at" timestamp with time zone
);
--> statement-breakpoint
CREATE TABLE "email_sync_state" (
	"email_account_id" uuid PRIMARY KEY NOT NULL,
	"last_sync_cursor" text,
	"last_synced_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "email_account_tokens" ADD CONSTRAINT "email_account_tokens_email_account_id_email_accounts_id_fk" FOREIGN KEY ("email_account_id") REFERENCES "public"."email_accounts"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "email_threads" ADD CONSTRAINT "email_threads_email_account_id_email_accounts_id_fk" FOREIGN KEY ("email_account_id") REFERENCES "public"."email_accounts"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "email_sync_state" ADD CONSTRAINT "email_sync_state_email_account_id_email_accounts_id_fk" FOREIGN KEY ("email_account_id") REFERENCES "public"."email_accounts"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "gmail_oauth_states_user_expires_idx" ON "gmail_oauth_states" ("user_id","expires_at");--> statement-breakpoint
CREATE INDEX "email_accounts_user_idx" ON "email_accounts" ("user_id");--> statement-breakpoint
CREATE UNIQUE INDEX "email_accounts_user_provider_unique" ON "email_accounts" ("user_id","provider");--> statement-breakpoint
CREATE INDEX "email_threads_user_last_message_idx" ON "email_threads" ("user_id","last_message_at");--> statement-breakpoint
CREATE INDEX "email_threads_account_last_message_idx" ON "email_threads" ("email_account_id","last_message_at");--> statement-breakpoint
CREATE UNIQUE INDEX "email_threads_account_gmail_thread_unique" ON "email_threads" ("email_account_id","gmail_thread_id");
