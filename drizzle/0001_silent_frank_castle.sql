DROP INDEX "activations_installation_unique";--> statement-breakpoint
CREATE INDEX "activations_installation_idx" ON "activations" USING btree ("installation_id");