import "server-only";

import { and, eq } from "drizzle-orm";

import { getDb } from "@/db/client";
import { activations, licenses } from "@/db/schema";
import { hashSecret, secretHashesEqual } from "@/server/crypto";

export type ActivationInput = {
  key: string;
  installationId: string;
  deviceModel: string;
  nickname: string;
  appVersion: string;
  appBuild: string;
};

async function findLicense(key: string) {
  const keyHash = hashSecret(key.trim());
  const [license] = await getDb()
    .select()
    .from(licenses)
    .where(eq(licenses.keyHash, keyHash))
    .limit(1);
  if (!license || !secretHashesEqual(license.keyHash, keyHash)) return null;
  return license;
}

async function activeResultIfCurrent<T extends { status: "active" }>(licenseId: string, result: T) {
  const [current] = await getDb()
    .select({ status: licenses.status })
    .from(licenses)
    .where(eq(licenses.id, licenseId))
    .limit(1);
  return current?.status === "active"
    ? result
    : { status: current?.status ?? ("invalid" as const) };
}

export async function activateLicense(input: ActivationInput) {
  const installationId = input.installationId.toLowerCase();
  const license = await findLicense(input.key);
  if (!license) return { status: "invalid" as const };
  if (license.status !== "active") return { status: license.status };

  const db = getDb();
  const [existing] = await db
    .select()
    .from(activations)
    .where(eq(activations.licenseId, license.id))
    .limit(1);
  if (existing) {
    return existing.installationId === installationId
      ? activeResultIfCurrent(license.id, {
          status: "active" as const,
          activatedAt: existing.createdAt,
        })
      : { status: "conflict" as const };
  }

  try {
    const [activation] = await db
      .insert(activations)
      .values({
        licenseId: license.id,
        installationId,
        deviceModel: input.deviceModel,
        nickname: input.nickname,
        appVersion: input.appVersion,
        appBuild: input.appBuild,
      })
      .returning();
    return activeResultIfCurrent(license.id, {
      status: "active" as const,
      activatedAt: activation.createdAt,
    });
  } catch (error) {
    // The unique license constraint settles simultaneous first-activation attempts.
    const [winner] = await db
      .select()
      .from(activations)
      .where(eq(activations.licenseId, license.id))
      .limit(1);
    if (winner) {
      return winner.installationId === installationId
        ? activeResultIfCurrent(license.id, {
            status: "active" as const,
            activatedAt: winner.createdAt,
          })
        : { status: "conflict" as const };
    }
    throw error;
  }
}

export async function validateLicense(key: string, installationId: string) {
  installationId = installationId.toLowerCase();
  const license = await findLicense(key);
  if (!license) return { status: "invalid" as const };
  if (license.status !== "active") return { status: license.status };
  const [activation] = await getDb()
    .select()
    .from(activations)
    .where(
      and(eq(activations.licenseId, license.id), eq(activations.installationId, installationId)),
    )
    .limit(1);
  if (!activation) return { status: "installation_mismatch" as const };
  await getDb()
    .update(activations)
    .set({ lastValidatedAt: new Date(), updatedAt: new Date() })
    .where(eq(activations.id, activation.id));
  return activeResultIfCurrent(license.id, { status: "active" as const });
}
