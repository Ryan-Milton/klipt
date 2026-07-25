ALTER TABLE "transactions" ADD COLUMN "status_occurred_at" timestamp with time zone;
UPDATE "transactions" SET "status_occurred_at" = "updated_at";
ALTER TABLE "transactions" ALTER COLUMN "status_occurred_at" SET NOT NULL;
