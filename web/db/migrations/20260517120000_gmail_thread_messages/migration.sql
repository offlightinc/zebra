CREATE TABLE "email_messages" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
	"user_id" text NOT NULL,
	"email_account_id" uuid NOT NULL,
	"email_thread_id" uuid NOT NULL,
	"gmail_thread_id" text NOT NULL,
	"gmail_message_id" text NOT NULL,
	"internet_message_id" text,
	"subject" text,
	"snippet" text,
	"from_name" text,
	"from_email" text,
	"to_recipients" text,
	"cc_recipients" text,
	"received_at" timestamp with time zone,
	"internal_date_ms" bigint,
	"is_unread" boolean DEFAULT false NOT NULL,
	"is_sent" boolean DEFAULT false NOT NULL,
	"has_attachment" boolean DEFAULT false NOT NULL,
	"label_ids" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"body_text" text,
	"body_html" text,
	"body_fetched_at" timestamp with time zone DEFAULT now() NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"deleted_at" timestamp with time zone
);
--> statement-breakpoint
ALTER TABLE "email_messages" ADD CONSTRAINT "email_messages_email_account_id_email_accounts_id_fk" FOREIGN KEY ("email_account_id") REFERENCES "public"."email_accounts"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "email_messages" ADD CONSTRAINT "email_messages_email_thread_id_email_threads_id_fk" FOREIGN KEY ("email_thread_id") REFERENCES "public"."email_threads"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "email_messages_account_thread_idx" ON "email_messages" ("email_account_id","gmail_thread_id");--> statement-breakpoint
CREATE INDEX "email_messages_thread_received_idx" ON "email_messages" ("email_thread_id","received_at");--> statement-breakpoint
CREATE INDEX "email_messages_user_received_idx" ON "email_messages" ("user_id","received_at");--> statement-breakpoint
CREATE UNIQUE INDEX "email_messages_account_gmail_message_unique" ON "email_messages" ("email_account_id","gmail_message_id");
