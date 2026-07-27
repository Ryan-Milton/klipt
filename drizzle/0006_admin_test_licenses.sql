CREATE TYPE "public"."license_origin" AS ENUM('paddle', 'admin');--> statement-breakpoint
ALTER TABLE "licenses" ALTER COLUMN "transaction_id" DROP NOT NULL;--> statement-breakpoint
ALTER TABLE "licenses" ADD COLUMN "origin" "license_origin" DEFAULT 'paddle' NOT NULL;--> statement-breakpoint
CREATE UNIQUE INDEX "licenses_active_admin_customer_unique" ON "licenses" USING btree ("customer_id") WHERE "licenses"."origin" = 'admin' AND "licenses"."status" = 'active';--> statement-breakpoint
ALTER TABLE "licenses" ADD CONSTRAINT "licenses_origin_transaction_check" CHECK (("licenses"."origin" = 'paddle' AND "licenses"."transaction_id" IS NOT NULL) OR ("licenses"."origin" = 'admin' AND "licenses"."transaction_id" IS NULL));