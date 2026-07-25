import "server-only";

import { and, eq, isNull, lte, ne, or, sql } from "drizzle-orm";

import { getDb } from "@/db/client";
import {
  customers,
  downloadGrants,
  licenses,
  releaseArtifacts,
  transactions,
  webhookEvents,
} from "@/db/schema";
import {
  decryptLicenseKey,
  decryptDownloadToken,
  encryptDownloadToken,
  encryptLicenseKey,
  generateLicenseKey,
  generateOpaqueToken,
  hashSecret,
} from "@/server/crypto";
import { env } from "@/server/env";
import {
  getPaddleCustomerEmail,
  getPaddleTransaction,
  isKliptTransaction,
  mapPaddleOutcome,
  type PaddleEvent,
} from "@/server/paddle";
import { fulfillmentEmail, sendTrackedEmail } from "@/server/resend";

function stringValue(value: unknown) {
  return typeof value === "string" && value ? value : null;
}

function minorTotal(data: Record<string, unknown>) {
  const details = data.details as Record<string, unknown> | undefined;
  const totals = details?.totals as Record<string, unknown> | undefined;
  const total = stringValue(totals?.total);
  return total && /^\d+$/.test(total) ? Number(total) : null;
}

function eventOccurredAt(event: PaddleEvent) {
  const value = new Date(event.occurred_at);
  if (Number.isNaN(value.getTime())) throw new Error("Paddle event timestamp is invalid");
  return value;
}

async function processCompletion(event: PaddleEvent) {
  if (!isKliptTransaction(event.data, env.paddle().PADDLE_PRICE_ID)) {
    throw new Error("Completion event does not match the configured Klipt product and price");
  }
  const transactionId = stringValue(event.data.id);
  const paddleCustomerId = stringValue(event.data.customer_id);
  if (!transactionId || !paddleCustomerId)
    throw new Error("Completion event lacks transaction/customer ID");

  const embeddedCustomer = event.data.customer as Record<string, unknown> | undefined;
  const email =
    stringValue(embeddedCustomer?.email)?.toLowerCase() ??
    (await getPaddleCustomerEmail(paddleCustomerId));
  const db = getDb();
  let [customer] = await db
    .select()
    .from(customers)
    .where(eq(customers.paddleCustomerId, paddleCustomerId))
    .limit(1);
  if (!customer) {
    [customer] = await db
      .insert(customers)
      .values({ email, paddleCustomerId })
      .onConflictDoUpdate({
        target: customers.email,
        set: { paddleCustomerId, updatedAt: new Date() },
      })
      .returning();
  }

  let [transaction] = await db
    .select()
    .from(transactions)
    .where(eq(transactions.paddleTransactionId, transactionId))
    .limit(1);
  if (!transaction) {
    [transaction] = await db
      .insert(transactions)
      .values({
        customerId: customer.id,
        paddleTransactionId: transactionId,
        status: "completed",
        currencyCode: stringValue(event.data.currency_code),
        totalMinor: minorTotal(event.data),
        occurredAt: eventOccurredAt(event),
        statusOccurredAt: eventOccurredAt(event),
      })
      .onConflictDoNothing()
      .returning();
    if (!transaction) {
      [transaction] = await db
        .select()
        .from(transactions)
        .where(eq(transactions.paddleTransactionId, transactionId))
        .limit(1);
    }
  }
  if (transaction.status !== "completed") return;

  let [license] = await db
    .select()
    .from(licenses)
    .where(eq(licenses.transactionId, transaction.id))
    .limit(1);
  let licenseKey: string;
  if (!license) {
    licenseKey = generateLicenseKey();
    [license] = await db
      .insert(licenses)
      .values({
        customerId: customer.id,
        transactionId: transaction.id,
        keyHash: hashSecret(licenseKey),
        encryptedKey: encryptLicenseKey(licenseKey),
        statusOccurredAt: eventOccurredAt(event),
      })
      .returning();
  } else {
    licenseKey = decryptLicenseKey(license.encryptedKey);
  }

  const [latestTransaction] = await db
    .select({ status: transactions.status, statusOccurredAt: transactions.statusOccurredAt })
    .from(transactions)
    .where(eq(transactions.id, transaction.id))
    .limit(1);
  if (!latestTransaction) throw new Error("Purchase transaction disappeared during fulfillment");
  if (latestTransaction.status !== "completed") {
    await db
      .update(licenses)
      .set({
        status: latestTransaction.status === "refunded" ? "refunded" : "revoked",
        statusOccurredAt: latestTransaction.statusOccurredAt,
        revokedReason:
          latestTransaction.status === "disputed" ? "Paddle dispute or chargeback" : null,
        updatedAt: new Date(),
      })
      .where(
        and(
          eq(licenses.id, license.id),
          lte(licenses.statusOccurredAt, latestTransaction.statusOccurredAt),
        ),
      );
    return;
  }

  const [artifact] = await db
    .select()
    .from(releaseArtifacts)
    .where(eq(releaseArtifacts.isCurrent, true))
    .limit(1);
  if (!artifact) throw new Error("No current release artifact is configured");

  let token: string;
  const [unusedGrant] = await db
    .select()
    .from(downloadGrants)
    .where(and(eq(downloadGrants.licenseId, license.id), isNull(downloadGrants.usedAt)))
    .limit(1);
  if (unusedGrant) {
    token = decryptDownloadToken(unusedGrant.encryptedToken);
  } else {
    const [anyGrant] = await db
      .select({ id: downloadGrants.id })
      .from(downloadGrants)
      .where(eq(downloadGrants.licenseId, license.id))
      .limit(1);
    if (anyGrant) return;
    token = generateOpaqueToken();
    await db.insert(downloadGrants).values({
      licenseId: license.id,
      artifactId: artifact.id,
      tokenHash: hashSecret(token),
      encryptedToken: encryptDownloadToken(token),
    });
  }

  const mail = fulfillmentEmail(licenseKey, token);
  await sendTrackedEmail({
    customerId: customer.id,
    to: email,
    kind: "fulfillment",
    idempotencyKey: `fulfillment-${license.id}`,
    ...mail,
  });
}

async function processAdverseOutcome(event: PaddleEvent, outcome: "refunded" | "disputed") {
  const transactionId = stringValue(event.data.transaction_id) ?? stringValue(event.data.id);
  if (!transactionId) throw new Error("Adverse event lacks a transaction ID");
  const db = getDb();
  const occurredAt = eventOccurredAt(event);
  const transactionConditions = [eq(transactions.paddleTransactionId, transactionId)];
  if (outcome === "disputed") {
    transactionConditions.push(
      ne(transactions.status, "refunded"),
      lte(transactions.statusOccurredAt, occurredAt),
    );
  }
  const [transaction] = await db
    .update(transactions)
    .set({ status: outcome, statusOccurredAt: occurredAt, updatedAt: new Date() })
    .where(and(...transactionConditions))
    .returning({ id: transactions.id });
  if (!transaction) {
    const [existing] = await db
      .select({ id: transactions.id })
      .from(transactions)
      .where(eq(transactions.paddleTransactionId, transactionId))
      .limit(1);
    if (existing) return;
    throw new Error("Purchase transaction is not available yet; retry this event");
  }
  const licenseConditions = [eq(licenses.transactionId, transaction.id)];
  if (outcome === "disputed") {
    licenseConditions.push(
      ne(licenses.status, "refunded"),
      lte(licenses.statusOccurredAt, occurredAt),
      or(
        eq(licenses.status, "active"),
        eq(licenses.revokedReason, "Paddle dispute or chargeback"),
      )!,
    );
  }
  const [license] = await db
    .update(licenses)
    .set({
      status: outcome === "refunded" ? "refunded" : "revoked",
      statusOccurredAt: occurredAt,
      revokedReason: outcome === "disputed" ? "Paddle dispute or chargeback" : null,
      updatedAt: new Date(),
    })
    .where(and(...licenseConditions))
    .returning({ id: licenses.id });
  if (!license) {
    const [existing] = await db
      .select({ id: licenses.id })
      .from(licenses)
      .where(eq(licenses.transactionId, transaction.id))
      .limit(1);
    if (existing) return;
    throw new Error("Purchase license is not available yet; retry this event");
  }
}

async function processRestoredOutcome(event: PaddleEvent) {
  const transactionId = stringValue(event.data.transaction_id) ?? stringValue(event.data.id);
  if (!transactionId) throw new Error("Restored dispute event lacks a transaction ID");
  const db = getDb();
  const occurredAt = eventOccurredAt(event);
  const [transaction] = await db
    .update(transactions)
    .set({ status: "completed", statusOccurredAt: occurredAt, updatedAt: new Date() })
    .where(
      and(
        eq(transactions.paddleTransactionId, transactionId),
        ne(transactions.status, "refunded"),
        lte(transactions.statusOccurredAt, occurredAt),
      ),
    )
    .returning({ id: transactions.id });
  if (!transaction) {
    const [existing] = await db
      .select({ id: transactions.id })
      .from(transactions)
      .where(eq(transactions.paddleTransactionId, transactionId))
      .limit(1);
    if (existing) return;
    throw new Error("Purchase transaction is not available yet; retry this event");
  }
  const [license] = await db
    .update(licenses)
    .set({
      status: "active",
      statusOccurredAt: occurredAt,
      revokedReason: null,
      updatedAt: new Date(),
    })
    .where(
      and(
        eq(licenses.transactionId, transaction.id),
        lte(licenses.statusOccurredAt, occurredAt),
        or(
          eq(licenses.status, "active"),
          eq(licenses.revokedReason, "Paddle dispute or chargeback"),
        ),
      ),
    )
    .returning({ id: licenses.id });
  if (!license) {
    const [existing] = await db
      .select({ id: licenses.id })
      .from(licenses)
      .where(eq(licenses.transactionId, transaction.id))
      .limit(1);
    if (existing) return;
    throw new Error("Purchase license is not available yet; retry this event");
  }
}

async function eventBelongsToKlipt(
  event: PaddleEvent,
  outcome: NonNullable<ReturnType<typeof mapPaddleOutcome>>,
) {
  const priceId = env.paddle().PADDLE_PRICE_ID;
  if (outcome === "completed") return isKliptTransaction(event.data, priceId);

  const transactionId = stringValue(event.data.transaction_id) ?? stringValue(event.data.id);
  if (!transactionId) throw new Error("Paddle adjustment lacks a transaction ID");
  const [localTransaction] = await getDb()
    .select({ id: transactions.id })
    .from(transactions)
    .where(eq(transactions.paddleTransactionId, transactionId))
    .limit(1);
  if (localTransaction) return true;

  return isKliptTransaction(await getPaddleTransaction(transactionId), priceId);
}

async function markWebhookProcessed(webhookId: string, claimStartedAt: Date) {
  await getDb()
    .update(webhookEvents)
    .set({
      status: "processed",
      processedAt: new Date(),
      lastError: null,
      attemptCount: sql`${webhookEvents.attemptCount} + 1`,
      updatedAt: new Date(),
    })
    .where(
      and(
        eq(webhookEvents.id, webhookId),
        eq(webhookEvents.status, "pending"),
        eq(webhookEvents.updatedAt, claimStartedAt),
      ),
    );
}

export async function processWebhookEvent(
  webhookId: string,
  event: PaddleEvent,
  claimStartedAt: Date,
) {
  const outcome = mapPaddleOutcome(event.event_type, event.data);
  try {
    if (!outcome || !(await eventBelongsToKlipt(event, outcome))) {
      await markWebhookProcessed(webhookId, claimStartedAt);
      return "ignored" as const;
    }
    if (outcome === "completed") await processCompletion(event);
    if (outcome === "refunded" || outcome === "disputed") {
      await processAdverseOutcome(event, outcome);
    }
    if (outcome === "restored") await processRestoredOutcome(event);
    await markWebhookProcessed(webhookId, claimStartedAt);
    return "processed" as const;
  } catch (error) {
    await getDb()
      .update(webhookEvents)
      .set({
        status: "failed",
        lastError:
          error instanceof Error ? error.message.slice(0, 500) : "Unknown processing error",
        attemptCount: sql`${webhookEvents.attemptCount} + 1`,
        updatedAt: new Date(),
      })
      .where(
        and(
          eq(webhookEvents.id, webhookId),
          eq(webhookEvents.status, "pending"),
          eq(webhookEvents.updatedAt, claimStartedAt),
        ),
      );
    throw error;
  }
}
