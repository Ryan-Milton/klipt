import { and, eq, isNull, ne } from "drizzle-orm";
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
import { fulfillmentEmail, sendTrackedEmail, testLicenseEmail } from "@/server/resend";
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
  z.object({
    action: z.literal("resend"),
    licenseId: z.uuid(),
    grantTokenHash: z.string().regex(/^[a-f0-9]{64}$/),
  }),
  z.object({ action: z.literal("retry"), webhookId: z.uuid() }),
]);

async function reissueUnusedGrant(licenseId: string, grantTokenHash: string) {
  const db = getDb();
  const token = generateOpaqueToken();
  const result = await db.transaction(async (tx) => {
    const [license] = await tx
      .select()
      .from(licenses)
      .where(eq(licenses.id, licenseId))
      .limit(1)
      .for("update");
    if (!license) throw new Error("License not found");
    if (license.status !== "active") throw new Error("Only active licenses can be reissued");
    const [grant] = await tx
      .select()
      .from(downloadGrants)
      .where(
        and(
          eq(downloadGrants.licenseId, licenseId),
          eq(downloadGrants.tokenHash, grantTokenHash),
          isNull(downloadGrants.usedAt),
        ),
      )
      .limit(1);
    if (!grant) throw new Error("Grant changed or was used; refresh before reissuing");
    const [customer] = await tx
      .select()
      .from(customers)
      .where(eq(customers.id, license.customerId))
      .limit(1);
    const [artifact] = await tx
      .select({ id: releaseArtifacts.id })
      .from(releaseArtifacts)
      .where(eq(releaseArtifacts.isCurrent, true))
      .limit(1);
    if (!customer || !artifact) throw new Error("Customer or current artifact is missing");
    const [rotated] = await tx
      .update(downloadGrants)
      .set({
        tokenHash: hashSecret(token),
        encryptedToken: encryptDownloadToken(token),
        artifactId: artifact.id,
        reissuedAt: new Date(),
        updatedAt: new Date(),
      })
      .where(
        and(
          eq(downloadGrants.id, grant.id),
          eq(downloadGrants.tokenHash, grantTokenHash),
          isNull(downloadGrants.usedAt),
        ),
      )
      .returning({ id: downloadGrants.id });
    if (!rotated) throw new Error("Grant changed or was used; refresh before reissuing");
    return { customer, license };
  });
  const mail =
    result.license.origin === "admin"
      ? testLicenseEmail(decryptLicenseKey(result.license.encryptedKey), token)
      : fulfillmentEmail(decryptLicenseKey(result.license.encryptedKey), token);
  await sendTrackedEmail({
    customerId: result.customer.id,
    to: result.customer.email,
    kind: result.license.origin === "admin" ? "test-license" : "fulfillment",
    idempotencyKey: `${result.license.origin === "admin" ? "test-license" : "fulfillment"}-reissue-${hashSecret(token)}`,
    ...mail,
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
        .select({
          origin: licenses.origin,
          customerId: licenses.customerId,
          transactionStatus: transactions.status,
          reason: licenses.revokedReason,
        })
        .from(licenses)
        .leftJoin(transactions, eq(transactions.id, licenses.transactionId))
        .where(eq(licenses.id, input.licenseId))
        .limit(1);
      if (
        !licenseState ||
        (licenseState.origin === "paddle" && licenseState.transactionStatus !== "completed") ||
        licenseState.reason === "Paddle dispute or chargeback"
      ) {
        throw new Error("Paddle-refunded or disputed licenses cannot be restored manually");
      }
      if (licenseState.origin === "admin") {
        const [otherActive] = await db
          .select({ id: licenses.id })
          .from(licenses)
          .where(
            and(
              eq(licenses.customerId, licenseState.customerId),
              eq(licenses.origin, "admin"),
              eq(licenses.status, "active"),
              ne(licenses.id, input.licenseId),
            ),
          )
          .limit(1);
        if (otherActive) throw new Error("Customer already has another active test license");
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
      await reissueUnusedGrant(input.licenseId, input.grantTokenHash);
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
