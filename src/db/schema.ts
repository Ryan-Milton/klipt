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

const timestamps = {
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
};

export const licenseStatus = pgEnum("license_status", ["active", "refunded", "revoked"]);
export const transactionStatus = pgEnum("transaction_status", [
  "completed",
  "refunded",
  "disputed",
]);
export const webhookStatus = pgEnum("webhook_status", ["pending", "processed", "failed"]);
export const emailStatus = pgEnum("email_status", ["pending", "sent", "failed"]);

export const customers = pgTable(
  "customers",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    email: text("email").notNull(),
    paddleCustomerId: text("paddle_customer_id"),
    ...timestamps,
  },
  (table) => [
    uniqueIndex("customers_email_unique").on(table.email),
    uniqueIndex("customers_paddle_id_unique").on(table.paddleCustomerId),
  ],
);

export const transactions = pgTable(
  "transactions",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    customerId: uuid("customer_id")
      .notNull()
      .references(() => customers.id),
    paddleTransactionId: text("paddle_transaction_id").notNull(),
    status: transactionStatus("status").notNull().default("completed"),
    currencyCode: text("currency_code"),
    totalMinor: integer("total_minor"),
    occurredAt: timestamp("occurred_at", { withTimezone: true }).notNull(),
    ...timestamps,
  },
  (table) => [uniqueIndex("transactions_paddle_id_unique").on(table.paddleTransactionId)],
);

export const licenses = pgTable(
  "licenses",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    customerId: uuid("customer_id")
      .notNull()
      .references(() => customers.id),
    transactionId: uuid("transaction_id")
      .notNull()
      .references(() => transactions.id),
    keyHash: text("key_hash").notNull(),
    encryptedKey: text("encrypted_key").notNull(),
    status: licenseStatus("status").notNull().default("active"),
    revokedReason: text("revoked_reason"),
    ...timestamps,
  },
  (table) => [
    uniqueIndex("licenses_key_hash_unique").on(table.keyHash),
    uniqueIndex("licenses_transaction_unique").on(table.transactionId),
    index("licenses_customer_idx").on(table.customerId),
  ],
);

export const activations = pgTable(
  "activations",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    licenseId: uuid("license_id")
      .notNull()
      .references(() => licenses.id),
    installationId: uuid("installation_id").notNull(),
    deviceModel: text("device_model").notNull(),
    nickname: text("nickname").notNull(),
    appVersion: text("app_version").notNull(),
    appBuild: text("app_build").notNull(),
    lastValidatedAt: timestamp("last_validated_at", { withTimezone: true }),
    ...timestamps,
  },
  (table) => [
    uniqueIndex("activations_license_unique").on(table.licenseId),
    index("activations_installation_idx").on(table.installationId),
  ],
);

export const releaseArtifacts = pgTable(
  "release_artifacts",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    version: text("version").notNull(),
    build: text("build").notNull(),
    r2ObjectKey: text("r2_object_key").notNull(),
    sha256: text("sha256").notNull(),
    sizeBytes: bigint("size_bytes", { mode: "number" }).notNull(),
    isCurrent: boolean("is_current").notNull().default(false),
    ...timestamps,
  },
  (table) => [
    uniqueIndex("release_artifacts_version_build_unique").on(table.version, table.build),
    uniqueIndex("release_artifacts_current_unique")
      .on(table.isCurrent)
      .where(sql`${table.isCurrent} = true`),
  ],
);

export const downloadGrants = pgTable(
  "download_grants",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    licenseId: uuid("license_id")
      .notNull()
      .references(() => licenses.id),
    artifactId: uuid("artifact_id")
      .notNull()
      .references(() => releaseArtifacts.id),
    tokenHash: text("token_hash").notNull(),
    encryptedToken: text("encrypted_token").notNull(),
    usedAt: timestamp("used_at", { withTimezone: true }),
    reissuedAt: timestamp("reissued_at", { withTimezone: true }),
    ...timestamps,
  },
  (table) => [
    uniqueIndex("download_grants_token_unique").on(table.tokenHash),
    uniqueIndex("download_grants_license_unique").on(table.licenseId),
  ],
);

export const customerMagicLinks = pgTable(
  "customer_magic_links",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    customerId: uuid("customer_id")
      .notNull()
      .references(() => customers.id),
    tokenHash: text("token_hash").notNull(),
    expiresAt: timestamp("expires_at", { withTimezone: true }).notNull(),
    usedAt: timestamp("used_at", { withTimezone: true }),
    ...timestamps,
  },
  (table) => [uniqueIndex("magic_links_token_unique").on(table.tokenHash)],
);

export const webhookEvents = pgTable(
  "webhook_events",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    providerEventId: text("provider_event_id").notNull(),
    eventType: text("event_type").notNull(),
    status: webhookStatus("status").notNull().default("pending"),
    sanitizedPayload: jsonb("sanitized_payload").notNull(),
    attemptCount: integer("attempt_count").notNull().default(0),
    lastError: text("last_error"),
    processedAt: timestamp("processed_at", { withTimezone: true }),
    ...timestamps,
  },
  (table) => [uniqueIndex("webhook_events_provider_id_unique").on(table.providerEventId)],
);

export const emailDeliveries = pgTable("email_deliveries", {
  id: uuid("id").primaryKey().defaultRandom(),
  customerId: uuid("customer_id").references(() => customers.id),
  kind: text("kind").notNull(),
  recipient: text("recipient").notNull(),
  providerMessageId: text("provider_message_id"),
  status: emailStatus("status").notNull().default("pending"),
  lastError: text("last_error"),
  ...timestamps,
});

export const adminNotes = pgTable("admin_notes", {
  id: uuid("id").primaryKey().defaultRandom(),
  licenseId: uuid("license_id")
    .notNull()
    .references(() => licenses.id),
  authorGithubId: text("author_github_id").notNull(),
  body: text("body").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
});

export const adminAudit = pgTable("admin_audit", {
  id: uuid("id").primaryKey().defaultRandom(),
  actorGithubId: text("actor_github_id").notNull(),
  action: text("action").notNull(),
  targetType: text("target_type").notNull(),
  targetId: text("target_id").notNull(),
  metadata: jsonb("metadata").notNull().default({}),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
});
