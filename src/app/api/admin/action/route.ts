import { and, eq, isNull } from "drizzle-orm";
import { NextResponse } from "next/server";
import { z } from "zod";

import { getDb } from "@/db/client";
import {
  adminAudit,
  adminNotes,
  customers,
  downloadGrants,
  licenses,
  releaseArtifacts,
  transactions,
  webhookEvents,
} from "@/db/schema";
import { auth } from "@/server/auth";
import {
  decryptLicenseKey,
  encryptDownloadToken,
  generateOpaqueToken,
  hashSecret,
} from "@/server/crypto";
import { type PaddleEvent } from "@/server/paddle";
import { fulfillmentEmail, sendTrackedEmail } from "@/server/resend";
import { processWebhookEvent } from "@/server/webhooks";

export const runtime = "nodejs";

const actionSchema = z.discriminatedUnion("action", [
  z.object({
    action: z.literal("revoke"),
    licenseId: z.uuid(),
    reason: z.string().trim().min(1).max(300),
  }),
  z.object({ action: z.literal("unrevoke"), licenseId: z.uuid() }),
  z.object({
    action: z.literal("note"),
    licenseId: z.uuid(),
    body: z.string().trim().min(1).max(2000),
  }),
  z.object({ action: z.literal("resend"), licenseId: z.uuid() }),
  z.object({ action: z.literal("retry"), webhookId: z.uuid() }),
]);

async function reissueUnusedGrant(licenseId: string) {
  const db = getDb();
  const [license] = await db.select().from(licenses).where(eq(licenses.id, licenseId)).limit(1);
  if (!license) throw new Error("License not found");
  const [grant] = await db
    .select()
    .from(downloadGrants)
    .where(and(eq(downloadGrants.licenseId, licenseId), isNull(downloadGrants.usedAt)))
    .limit(1);
  if (!grant) throw new Error("Initial download was used; reissue is not permitted");
  const [customer] = await db
    .select()
    .from(customers)
    .where(eq(customers.id, license.customerId))
    .limit(1);
  const [artifact] = await db
    .select({ id: releaseArtifacts.id })
    .from(releaseArtifacts)
    .where(eq(releaseArtifacts.isCurrent, true))
    .limit(1);
  if (!customer || !artifact) throw new Error("Customer or current artifact is missing");
  const token = generateOpaqueToken();
  await db
    .update(downloadGrants)
    .set({
      tokenHash: hashSecret(token),
      encryptedToken: encryptDownloadToken(token),
      artifactId: artifact.id,
      reissuedAt: new Date(),
      updatedAt: new Date(),
    })
    .where(eq(downloadGrants.id, grant.id));
  await sendTrackedEmail({
    customerId: customer.id,
    to: customer.email,
    kind: "fulfillment",
    idempotencyKey: `fulfillment-reissue-${hashSecret(token)}`,
    ...fulfillmentEmail(decryptLicenseKey(license.encryptedKey), token),
  });
}

export async function POST(request: Request) {
  const requestUrl = new URL(request.url);
  if (request.headers.get("origin") !== requestUrl.origin) {
    return NextResponse.json({ error: "Invalid origin" }, { status: 403 });
  }
  const session = await auth();
  if (!session?.user.githubId) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  const formData = await request.formData();
  const parsed = actionSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) return NextResponse.json({ error: "Invalid action" }, { status: 400 });

  const db = getDb();
  const input = parsed.data;
  const targetId = "licenseId" in input ? input.licenseId : input.webhookId;
  try {
    await db.insert(adminAudit).values({
      actorGithubId: session.user.githubId,
      action: input.action,
      targetType: input.action === "retry" ? "webhook" : "license",
      targetId,
      metadata: {
        outcome: "attempted",
        ...(input.action === "revoke" ? { reason: input.reason } : {}),
      },
    });
    if (input.action === "revoke") {
      await db
        .update(licenses)
        .set({
          status: "revoked",
          statusOccurredAt: new Date(),
          revokedReason: input.reason,
          updatedAt: new Date(),
        })
        .where(eq(licenses.id, input.licenseId));
    } else if (input.action === "unrevoke") {
      const [licenseState] = await db
        .select({ transactionStatus: transactions.status, reason: licenses.revokedReason })
        .from(licenses)
        .innerJoin(transactions, eq(transactions.id, licenses.transactionId))
        .where(eq(licenses.id, input.licenseId))
        .limit(1);
      if (
        !licenseState ||
        licenseState.transactionStatus !== "completed" ||
        licenseState.reason === "Paddle dispute or chargeback"
      ) {
        throw new Error("Paddle-refunded or disputed licenses cannot be restored manually");
      }
      const [changed] = await db
        .update(licenses)
        .set({
          status: "active",
          statusOccurredAt: new Date(),
          revokedReason: null,
          updatedAt: new Date(),
        })
        .where(and(eq(licenses.id, input.licenseId), eq(licenses.status, "revoked")))
        .returning({ id: licenses.id });
      if (!changed) throw new Error("Only a revoked license can be unrevoked");
    } else if (input.action === "note") {
      await db.insert(adminNotes).values({
        licenseId: input.licenseId,
        authorGithubId: session.user.githubId,
        body: input.body,
      });
    } else if (input.action === "resend") {
      await reissueUnusedGrant(input.licenseId);
    } else {
      const claimStartedAt = new Date();
      const [webhook] = await db
        .update(webhookEvents)
        .set({ status: "pending", lastError: null, updatedAt: claimStartedAt })
        .where(and(eq(webhookEvents.id, input.webhookId), eq(webhookEvents.status, "failed")))
        .returning();
      if (!webhook) throw new Error("Only failed webhooks can be retried");
      await processWebhookEvent(
        webhook.id,
        webhook.sanitizedPayload as PaddleEvent,
        claimStartedAt,
      );
    }
    return NextResponse.redirect(new URL("/admin?result=success", request.url), 303);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Action failed";
    console.error("Admin action failed", message);
    return NextResponse.redirect(
      new URL(`/admin?result=${encodeURIComponent(message)}`, request.url),
      303,
    );
  }
}
