import { eq } from "drizzle-orm";
import { NextResponse } from "next/server";
import { z } from "zod";

import { getDb } from "@/db/client";
import { webhookEvents } from "@/db/schema";
import { env } from "@/server/env";
import { sanitizePaddleEvent, verifyPaddleSignature } from "@/server/paddle";
import { processWebhookEvent } from "@/server/webhooks";

export const runtime = "nodejs";

const eventSchema = z.object({
  event_id: z.string().min(1),
  event_type: z.string().min(1),
  occurred_at: z.iso.datetime(),
  data: z.record(z.string(), z.unknown()),
});

export async function POST(request: Request) {
  const rawBody = await request.text();
  const signature = request.headers.get("paddle-signature") ?? "";
  let secret: string;
  try {
    secret = env.paddleWebhook().PADDLE_WEBHOOK_SECRET;
  } catch (error) {
    console.error(
      "Paddle webhook configuration error",
      error instanceof Error ? error.message : "Unknown",
    );
    return NextResponse.json({ error: "Webhook unavailable" }, { status: 503 });
  }
  if (!verifyPaddleSignature(rawBody, signature, secret)) {
    return NextResponse.json({ error: "Invalid signature" }, { status: 401 });
  }
  let payload: unknown;
  try {
    payload = JSON.parse(rawBody);
  } catch {
    return NextResponse.json({ error: "Invalid JSON" }, { status: 400 });
  }
  const parsed = eventSchema.safeParse(payload);
  if (!parsed.success) return NextResponse.json({ error: "Invalid event" }, { status: 400 });

  const event = sanitizePaddleEvent(parsed.data);
  const db = getDb();
  const [stored] = await db
    .insert(webhookEvents)
    .values({
      providerEventId: event.event_id,
      eventType: event.event_type,
      sanitizedPayload: event,
    })
    .onConflictDoNothing()
    .returning();
  if (!stored) {
    const [existing] = await db
      .select({ id: webhookEvents.id, status: webhookEvents.status })
      .from(webhookEvents)
      .where(eq(webhookEvents.providerEventId, event.event_id))
      .limit(1);
    if (!existing)
      return NextResponse.json({ error: "Webhook state unavailable" }, { status: 503 });
    if (existing.status === "processed") {
      return NextResponse.json({ received: true, duplicate: true, status: existing.status });
    }
    if (existing.status === "pending") {
      return NextResponse.json({ received: true, processing: "pending" }, { status: 503 });
    }
    try {
      await processWebhookEvent(existing.id, event);
      return NextResponse.json({ received: true, duplicate: true, retried: true });
    } catch {
      return NextResponse.json({ received: true, processing: "failed" }, { status: 500 });
    }
  }

  try {
    await processWebhookEvent(stored.id, event);
  } catch {
    return NextResponse.json({ received: true, processing: "failed" }, { status: 500 });
  }
  return NextResponse.json({ received: true });
}
