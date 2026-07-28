import "server-only";

import { and, eq, sql } from "drizzle-orm";

import { getDb } from "@/db/client";
import { adminAudit, customers, downloadGrants, licenses, releaseArtifacts } from "@/db/schema";
import {
  encryptDownloadToken,
  encryptLicenseKey,
  generateLicenseKey,
  generateOpaqueToken,
  hashSecret,
} from "@/server/crypto";
import { sendTrackedEmail, testLicenseEmail } from "@/server/resend";

export async function issueTestLicense(email: string, actorGithubId: string) {
  email = email.trim().toLowerCase();
  const licenseKey = generateLicenseKey();
  const token = generateOpaqueToken();
  const now = new Date();
  const db = getDb();
  const issued = await db.transaction(async (tx) => {
    await tx.execute(sql`SELECT pg_advisory_xact_lock(hashtext(${email}))`);

    let [customer] = await tx.select().from(customers).where(eq(customers.email, email)).limit(1);
    if (!customer) {
      [customer] = await tx.insert(customers).values({ email }).onConflictDoNothing().returning();
      if (!customer) {
        [customer] = await tx.select().from(customers).where(eq(customers.email, email)).limit(1);
      }
    }
    if (!customer) throw new Error("Customer could not be created");

    const [existing] = await tx
      .select({ id: licenses.id })
      .from(licenses)
      .where(
        and(
          eq(licenses.customerId, customer.id),
          eq(licenses.origin, "admin"),
          eq(licenses.status, "active"),
        ),
      )
      .limit(1);
    if (existing) {
      throw new Error("This email already has an active test license; use Reissue + email");
    }

    const [artifact] = await tx
      .select({ id: releaseArtifacts.id })
      .from(releaseArtifacts)
      .where(eq(releaseArtifacts.isCurrent, true))
      .limit(1);
    if (!artifact) throw new Error("No current release artifact is configured");

    const [license] = await tx
      .insert(licenses)
      .values({
        customerId: customer.id,
        origin: "admin",
        keyHash: hashSecret(licenseKey),
        encryptedKey: encryptLicenseKey(licenseKey),
        statusOccurredAt: now,
      })
      .returning({ id: licenses.id });
    await tx.insert(downloadGrants).values({
      licenseId: license.id,
      artifactId: artifact.id,
      tokenHash: hashSecret(token),
      encryptedToken: encryptDownloadToken(token),
    });
    await tx.insert(adminAudit).values({
      actorGithubId,
      action: "issue",
      targetType: "license",
      targetId: license.id,
      metadata: { outcome: "issued", origin: "admin" },
    });
    return { customerId: customer.id, licenseId: license.id };
  });

  await sendTrackedEmail({
    customerId: issued.customerId,
    to: email,
    kind: "test-license",
    idempotencyKey: `test-license-${issued.licenseId}`,
    ...testLicenseEmail(licenseKey, token),
  });
  return issued;
}
