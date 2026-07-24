CREATE TYPE "public"."email_status" AS ENUM('pending', 'sent', 'failed');--> statement-breakpoint
CREATE TYPE "public"."license_status" AS ENUM('active', 'refunded', 'revoked');--> statement-breakpoint
CREATE TYPE "public"."transaction_status" AS ENUM('completed', 'refunded', 'disputed');--> statement-breakpoint
CREATE TYPE "public"."webhook_status" AS ENUM('pending', 'processed', 'failed');--> statement-breakpoint
CREATE TABLE "activations" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"license_id" uuid NOT NULL,
	"installation_id" uuid NOT NULL,
	"device_model" text NOT NULL,
	"nickname" text NOT NULL,
	"app_version" text NOT NULL,
	"app_build" text NOT NULL,
	"last_validated_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "admin_audit" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"actor_github_id" text NOT NULL,
	"action" text NOT NULL,
	"target_type" text NOT NULL,
	"target_id" text NOT NULL,
	"metadata" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "admin_notes" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"license_id" uuid NOT NULL,
	"author_github_id" text NOT NULL,
	"body" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "customer_magic_links" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"customer_id" uuid NOT NULL,
	"token_hash" text NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	"used_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "customers" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"email" text NOT NULL,
	"paddle_customer_id" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "download_grants" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"license_id" uuid NOT NULL,
	"artifact_id" uuid NOT NULL,
	"token_hash" text NOT NULL,
	"used_at" timestamp with time zone,
	"reissued_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "email_deliveries" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"customer_id" uuid,
	"kind" text NOT NULL,
	"recipient" text NOT NULL,
	"provider_message_id" text,
	"status" "email_status" DEFAULT 'pending' NOT NULL,
	"last_error" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "licenses" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"customer_id" uuid NOT NULL,
	"transaction_id" uuid NOT NULL,
	"key_hash" text NOT NULL,
	"encrypted_key" text NOT NULL,
	"status" "license_status" DEFAULT 'active' NOT NULL,
	"revoked_reason" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "release_artifacts" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"version" text NOT NULL,
	"build" text NOT NULL,
	"r2_object_key" text NOT NULL,
	"sha256" text NOT NULL,
	"size_bytes" bigint NOT NULL,
	"is_current" boolean DEFAULT false NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "transactions" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"customer_id" uuid NOT NULL,
	"paddle_transaction_id" text NOT NULL,
	"status" "transaction_status" DEFAULT 'completed' NOT NULL,
	"currency_code" text,
	"total_minor" integer,
	"occurred_at" timestamp with time zone NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "webhook_events" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"provider_event_id" text NOT NULL,
	"event_type" text NOT NULL,
	"status" "webhook_status" DEFAULT 'pending' NOT NULL,
	"sanitized_payload" jsonb NOT NULL,
	"attempt_count" integer DEFAULT 0 NOT NULL,
	"last_error" text,
	"processed_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "activations" ADD CONSTRAINT "activations_license_id_licenses_id_fk" FOREIGN KEY ("license_id") REFERENCES "public"."licenses"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "admin_notes" ADD CONSTRAINT "admin_notes_license_id_licenses_id_fk" FOREIGN KEY ("license_id") REFERENCES "public"."licenses"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "customer_magic_links" ADD CONSTRAINT "customer_magic_links_customer_id_customers_id_fk" FOREIGN KEY ("customer_id") REFERENCES "public"."customers"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "download_grants" ADD CONSTRAINT "download_grants_license_id_licenses_id_fk" FOREIGN KEY ("license_id") REFERENCES "public"."licenses"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "download_grants" ADD CONSTRAINT "download_grants_artifact_id_release_artifacts_id_fk" FOREIGN KEY ("artifact_id") REFERENCES "public"."release_artifacts"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "email_deliveries" ADD CONSTRAINT "email_deliveries_customer_id_customers_id_fk" FOREIGN KEY ("customer_id") REFERENCES "public"."customers"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "licenses" ADD CONSTRAINT "licenses_customer_id_customers_id_fk" FOREIGN KEY ("customer_id") REFERENCES "public"."customers"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "licenses" ADD CONSTRAINT "licenses_transaction_id_transactions_id_fk" FOREIGN KEY ("transaction_id") REFERENCES "public"."transactions"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "transactions" ADD CONSTRAINT "transactions_customer_id_customers_id_fk" FOREIGN KEY ("customer_id") REFERENCES "public"."customers"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "activations_license_unique" ON "activations" USING btree ("license_id");--> statement-breakpoint
CREATE UNIQUE INDEX "activations_installation_unique" ON "activations" USING btree ("installation_id");--> statement-breakpoint
CREATE UNIQUE INDEX "magic_links_token_unique" ON "customer_magic_links" USING btree ("token_hash");--> statement-breakpoint
CREATE UNIQUE INDEX "customers_email_unique" ON "customers" USING btree ("email");--> statement-breakpoint
CREATE UNIQUE INDEX "customers_paddle_id_unique" ON "customers" USING btree ("paddle_customer_id");--> statement-breakpoint
CREATE UNIQUE INDEX "download_grants_token_unique" ON "download_grants" USING btree ("token_hash");--> statement-breakpoint
CREATE UNIQUE INDEX "download_grants_license_unique" ON "download_grants" USING btree ("license_id");--> statement-breakpoint
CREATE UNIQUE INDEX "licenses_key_hash_unique" ON "licenses" USING btree ("key_hash");--> statement-breakpoint
CREATE UNIQUE INDEX "licenses_transaction_unique" ON "licenses" USING btree ("transaction_id");--> statement-breakpoint
CREATE INDEX "licenses_customer_idx" ON "licenses" USING btree ("customer_id");--> statement-breakpoint
CREATE UNIQUE INDEX "release_artifacts_current_unique" ON "release_artifacts" USING btree ("is_current") WHERE "release_artifacts"."is_current" = true;--> statement-breakpoint
CREATE UNIQUE INDEX "transactions_paddle_id_unique" ON "transactions" USING btree ("paddle_transaction_id");--> statement-breakpoint
CREATE UNIQUE INDEX "webhook_events_provider_id_unique" ON "webhook_events" USING btree ("provider_event_id");