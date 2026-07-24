import "server-only";

import { and, eq, isNull, sql } from "drizzle-orm";

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
import { getPaddleCustomerEmail, mapPaddleOutcome, type PaddleEvent } from "@/server/paddle";
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

async function processCompletion(event: PaddleEvent) {
  const customData = event.data.custom_data as Record<string, unknown> | undefined;
  const items = Array.isArray(event.data.items)
    ? (event.data.items as Array<Record<string, unknown>>)
    : [];
  if (
    customData?.product !== "klipt_macos_lifetime" ||
    !items.some((item) => item.price_id === env.paddle().PADDLE_PRICE_ID)
  ) {
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
        occurredAt: new Date(event.occurred_at),
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
      })
      .returning();
  } else {
    licenseKey = decryptLicenseKey(license.encryptedKey);
  }

  const [latestTransaction] = await db
    .select({ status: transactions.status })
    .from(transactions)
    .where(eq(transactions.id, transaction.id))
    .limit(1);
  if (!latestTransaction) throw new Error("Purchase transaction disappeared during fulfillment");
  if (latestTransaction.status !== "completed") {
    await db
      .update(licenses)
      .set({
        status: latestTransaction.status === "refunded" ? "refunded" : "revoked",
        revokedReason:
          latestTransaction.status === "disputed" ? "Paddle dispute or chargeback" : null,
        updatedAt: new Date(),
      })
      .where(eq(licenses.id, license.id));
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
  const [transaction] = await db
    .update(transactions)
    .set({ status: outcome, updatedAt: new Date() })
    .where(eq(transactions.paddleTransactionId, transactionId))
    .returning({ id: transactions.id });
  if (!transaction) throw new Error("Purchase transaction is not available yet; retry this event");
  const [license] = await db
    .update(licenses)
    .set({
      status: outcome === "refunded" ? "refunded" : "revoked",
      revokedReason: outcome === "disputed" ? "Paddle dispute or chargeback" : null,
      updatedAt: new Date(),
    })
    .where(eq(licenses.transactionId, transaction.id))
    .returning({ id: licenses.id });
  if (!license) throw new Error("Purchase license is not available yet; retry this event");
}

async function processRestoredOutcome(event: PaddleEvent) {
  const transactionId = stringValue(event.data.transaction_id) ?? stringValue(event.data.id);
  if (!transactionId) throw new Error("Restored dispute event lacks a transaction ID");
  const db = getDb();
  const [transaction] = await db
    .update(transactions)
    .set({ status: "completed", updatedAt: new Date() })
    .where(eq(transactions.paddleTransactionId, transactionId))
    .returning({ id: transactions.id });
  if (!transaction) throw new Error("Purchase transaction is not available yet; retry this event");
  await db
    .update(licenses)
    .set({ status: "active", revokedReason: null, updatedAt: new Date() })
    .where(
      and(
        eq(licenses.transactionId, transaction.id),
        eq(licenses.revokedReason, "Paddle dispute or chargeback"),
      ),
    );
}

export async function processWebhookEvent(webhookId: string, event: PaddleEvent) {
  const outcome = mapPaddleOutcome(event.event_type, event.data);
  try {
    if (outcome === "completed") await processCompletion(event);
    if (outcome === "refunded" || outcome === "disputed") {
      await processAdverseOutcome(event, outcome);
    }
    if (outcome === "restored") await processRestoredOutcome(event);
    await getDb()
      .update(webhookEvents)
      .set({
        status: "processed",
        processedAt: new Date(),
        lastError: null,
        attemptCount: sql`${webhookEvents.attemptCount} + 1`,
        updatedAt: new Date(),
      })
      .where(eq(webhookEvents.id, webhookId));
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
      .where(eq(webhookEvents.id, webhookId));
    throw error;
  }
}
