import { and, eq, lte, or } from "drizzle-orm";
import { NextResponse } from "next/server";
import { z } from "zod";

import { getDb } from "@/db/client";
import { webhookEvents } from "@/db/schema";
import { env } from "@/server/env";
import { isKliptTransaction, sanitizePaddleEvent, verifyPaddleSignature } from "@/server/paddle";
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
  if (event.event_type === "transaction.completed") {
    try {
      if (!isKliptTransaction(event.data, env.paddle().PADDLE_PRICE_ID)) {
        return NextResponse.json({ received: true, ignored: true });
      }
    } catch (error) {
      console.error(
        "Paddle completion classification error",
        error instanceof Error ? error.message : "Unknown",
      );
      return NextResponse.json({ received: true, processing: "failed" }, { status: 500 });
    }
  }
  const db = getDb();
  const receivedAt = new Date();
  const [stored] = await db
    .insert(webhookEvents)
    .values({
      providerEventId: event.event_id,
      eventType: event.event_type,
      sanitizedPayload: event,
      updatedAt: receivedAt,
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
    const claimStartedAt = new Date();
    const [claimed] = await db
      .update(webhookEvents)
      .set({ status: "pending", lastError: null, updatedAt: claimStartedAt })
      .where(
        and(
          eq(webhookEvents.id, existing.id),
          or(
            eq(webhookEvents.status, "failed"),
            and(
              eq(webhookEvents.status, "pending"),
              lte(webhookEvents.updatedAt, new Date(Date.now() - 10 * 60_000)),
            ),
          ),
        ),
      )
      .returning({ id: webhookEvents.id });
    if (!claimed) {
      return NextResponse.json({ received: true, processing: "pending" }, { status: 503 });
    }
    try {
      const result = await processWebhookEvent(claimed.id, event, claimStartedAt);
      return NextResponse.json({
        received: true,
        duplicate: true,
        retried: true,
        ignored: result === "ignored",
      });
    } catch {
      return NextResponse.json({ received: true, processing: "failed" }, { status: 500 });
    }
  }

  try {
    const result = await processWebhookEvent(stored.id, event, receivedAt);
    return NextResponse.json({ received: true, ignored: result === "ignored" });
  } catch {
    return NextResponse.json({ received: true, processing: "failed" }, { status: 500 });
  }
}
