import "server-only";

import { createHmac, timingSafeEqual } from "node:crypto";

import { env } from "@/server/env";

const SIGNATURE_TOLERANCE_SECONDS = 300;
const REQUEST_TIMEOUT_MS = 10_000;
const KLIPT_PRODUCT_MARKER = "klipt_macos_lifetime";

export type PaddleEvent = {
  event_id: string;
  event_type: string;
  occurred_at: string;
  data: Record<string, unknown>;
};

export function verifyPaddleSignature(
  rawBody: string,
  signatureHeader: string,
  secret: string,
  nowSeconds = Math.floor(Date.now() / 1000),
) {
  const parts = signatureHeader.split(";").map((part) => part.split("=", 2));
  const timestamp = parts.find(([key]) => key === "ts")?.[1];
  const signatures = parts.filter(([key]) => key === "h1").map(([, value]) => value);
  if (!timestamp || signatures.length === 0 || !/^\d+$/.test(timestamp)) return false;
  if (Math.abs(nowSeconds - Number(timestamp)) > SIGNATURE_TOLERANCE_SECONDS) return false;

  const expected = createHmac("sha256", secret).update(`${timestamp}:${rawBody}`).digest();
  return signatures.some((signature) => {
    try {
      const provided = Buffer.from(signature, "hex");
      return provided.length === expected.length && timingSafeEqual(provided, expected);
    } catch {
      return false;
    }
  });
}

export async function getPaddleCustomerEmail(customerId: string) {
  const config = env.paddle();
  const response = await fetch(`${config.PADDLE_API_BASE}/customers/${customerId}`, {
    headers: { Authorization: `Bearer ${config.PADDLE_API_KEY}` },
    cache: "no-store",
    signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
  });
  if (!response.ok) throw new Error(`Paddle customer request failed (${response.status})`);
  const payload = (await response.json()) as { data?: { email?: string } };
  if (!payload.data?.email) throw new Error("Paddle customer has no email address");
  return payload.data.email.toLowerCase();
}

export async function getPaddleTransaction(transactionId: string) {
  const config = env.paddle();
  const response = await fetch(
    `${config.PADDLE_API_BASE}/transactions/${encodeURIComponent(transactionId)}`,
    {
      headers: { Authorization: `Bearer ${config.PADDLE_API_KEY}` },
      cache: "no-store",
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    },
  );
  if (!response.ok) throw new Error(`Paddle transaction request failed (${response.status})`);
  const payload = (await response.json()) as { data?: unknown };
  if (!isRecord(payload.data)) throw new Error("Paddle transaction response is invalid");
  return payload.data;
}

export function isKliptTransaction(data: Record<string, unknown>, priceId: string) {
  if (!Array.isArray(data.items)) throw new Error("Paddle transaction items are invalid");
  if (data.items.length === 0) throw new Error("Paddle transaction has no items");
  if (data.custom_data != null && !isRecord(data.custom_data)) {
    throw new Error("Paddle transaction custom data is invalid");
  }
  const customData = isRecord(data.custom_data) ? data.custom_data : null;
  const hasMarker = customData?.product === KLIPT_PRODUCT_MARKER;
  const hasPrice = data.items.some((value) => {
    if (!isRecord(value)) throw new Error("Paddle transaction item is invalid");
    const price = isRecord(value.price) ? value.price : null;
    const itemPriceId = value.price_id ?? price?.id;
    if (typeof itemPriceId !== "string" || !itemPriceId) {
      throw new Error("Paddle transaction item has no price ID");
    }
    return itemPriceId === priceId;
  });
  if (hasMarker !== hasPrice) {
    throw new Error("Paddle transaction has inconsistent Klipt product metadata");
  }
  return hasMarker;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function sanitizePaddleEvent(event: PaddleEvent): PaddleEvent {
  const data = event.data;
  const customer = (data.customer as Record<string, unknown> | undefined) ?? {};
  const customData = isRecord(data.custom_data) ? data.custom_data : {};
  const details = (data.details as Record<string, unknown> | undefined) ?? {};
  const items = Array.isArray(data.items)
    ? data.items.map((value) => {
        const item = (value as Record<string, unknown>) ?? {};
        const price = (item.price as Record<string, unknown> | undefined) ?? {};
        return { price_id: item.price_id ?? price.id };
      })
    : [];
  return {
    event_id: event.event_id,
    event_type: event.event_type,
    occurred_at: event.occurred_at,
    data: {
      id: data.id,
      customer_id: data.customer_id,
      customer: { email: customer.email },
      status: data.status,
      currency_code: data.currency_code,
      details: { totals: details.totals },
      transaction_id: data.transaction_id,
      action: data.action,
      custom_data: { product: customData.product },
      items,
    },
  };
}

export function mapPaddleOutcome(eventType: string, data: Record<string, unknown>) {
  if (eventType === "transaction.completed") return "completed" as const;
  const action = String(data.action ?? "").toLowerCase();
  const status = String(data.status ?? "").toLowerCase();
  if (
    action === "chargeback_reverse" ||
    action === "chargeback_warning_reverse" ||
    eventType.includes("chargeback.reversed") ||
    eventType.includes("dispute.won")
  ) {
    return "restored" as const;
  }
  if (
    eventType.includes("chargeback") ||
    eventType.includes("dispute") ||
    action === "chargeback" ||
    action === "chargeback_warning" ||
    action === "dispute"
  ) {
    return "disputed" as const;
  }
  if (
    eventType.includes("refund") ||
    (eventType.includes("adjustment") && action === "refund" && status === "approved")
  ) {
    return "refunded" as const;
  }
  return null;
}
