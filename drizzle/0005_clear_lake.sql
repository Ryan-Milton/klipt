ALTER TABLE "licenses" ADD COLUMN "status_occurred_at" timestamp with time zone;
UPDATE "licenses" SET "status_occurred_at" = "updated_at";
ALTER TABLE "licenses" ALTER COLUMN "status_occurred_at" SET NOT NULL;
