import "server-only";

import { createHmac, timingSafeEqual } from "node:crypto";

import { env } from "@/server/env";

export const customerSessionCookie =
  process.env.NODE_ENV === "production" ? "__Secure-klipt.customer" : "klipt.customer";

export function createCustomerSession(customerId: string, now = Date.now()) {
  const payload = Buffer.from(
    JSON.stringify({ customerId, expiresAt: now + 15 * 60_000 }),
    "utf8",
  ).toString("base64url");
  return `${payload}.${sign(payload)}`;
}

export function readCustomerSession(value: string | undefined, now = Date.now()) {
  if (!value) return null;
  const [payload, suppliedSignature] = value.split(".");
  if (!payload || !suppliedSignature) return null;
  const expectedSignature = sign(payload);
  const supplied = Buffer.from(suppliedSignature, "base64url");
  const expected = Buffer.from(expectedSignature, "base64url");
  if (supplied.length !== expected.length || !timingSafeEqual(supplied, expected)) return null;
  try {
    const parsed = JSON.parse(Buffer.from(payload, "base64url").toString("utf8")) as {
      customerId?: unknown;
      expiresAt?: unknown;
    };
    if (
      typeof parsed.customerId !== "string" ||
      !/^[0-9a-f-]{36}$/i.test(parsed.customerId) ||
      typeof parsed.expiresAt !== "number" ||
      parsed.expiresAt <= now
    ) {
      return null;
    }
    return parsed.customerId;
  } catch {
    return null;
  }
}

function sign(payload: string) {
  return createHmac("sha256", env.customerSession().CUSTOMER_SESSION_SECRET)
    .update(payload)
    .digest("base64url");
}
