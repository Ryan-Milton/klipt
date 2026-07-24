import "server-only";

import { eq } from "drizzle-orm";
import { Resend } from "resend";

import { getDb } from "@/db/client";
import { emailDeliveries } from "@/db/schema";
import { env } from "@/server/env";

type Mail = {
  customerId?: string;
  to: string;
  subject: string;
  html: string;
  kind: "fulfillment" | "account-link";
  idempotencyKey?: string;
};

export async function sendTrackedEmail(mail: Mail) {
  const config = env.resend();
  const db = getDb();
  const [delivery] = await db
    .insert(emailDeliveries)
    .values({ customerId: mail.customerId, kind: mail.kind, recipient: mail.to })
    .returning({ id: emailDeliveries.id });
  try {
    const result = await new Resend(config.RESEND_API_KEY).emails.send(
      {
        from: config.EMAIL_FROM,
        to: mail.to,
        subject: mail.subject,
        html: mail.html,
      },
      { idempotencyKey: mail.idempotencyKey },
    );
    if (result.error) throw new Error(result.error.message);
    await db
      .update(emailDeliveries)
      .set({ status: "sent", providerMessageId: result.data?.id, updatedAt: new Date() })
      .where(eq(emailDeliveries.id, delivery.id));
  } catch (error) {
    await db
      .update(emailDeliveries)
      .set({
        status: "failed",
        lastError: error instanceof Error ? error.message.slice(0, 500) : "Unknown mail failure",
        updatedAt: new Date(),
      })
      .where(eq(emailDeliveries.id, delivery.id));
    throw error;
  }
}

export function fulfillmentEmail(licenseKey: string, token: string) {
  const appUrl = env.resend().NEXT_PUBLIC_APP_URL;
  return {
    subject: "Your Klipt license and download",
    html: `<h1>Everything you copy, ready.</h1><p>Your Klipt license key:</p><p><code>${licenseKey}</code></p><p><a href="${appUrl}/download/${token}">Download Klipt once</a></p><p>This installer link is single-use. Keep your license key somewhere safe. One license activates one Mac and cannot be transferred or recovered after installer redemption.</p>`,
  };
}

export function accountLinkEmail(token: string) {
  const appUrl = env.resend().NEXT_PUBLIC_APP_URL;
  return {
    subject: "Your Klipt account link",
    html: `<p><a href="${appUrl}/account/${token}">Open your Klipt purchase</a></p><p>This one-time link expires in 15 minutes. It does not provide a new installer download.</p>`,
  };
}
