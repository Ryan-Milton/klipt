import { and, desc, eq, gt, sql } from "drizzle-orm";
import { NextResponse } from "next/server";
import { z } from "zod";

import { getDb } from "@/db/client";
import { customerMagicLinks, customers } from "@/db/schema";
import { generateOpaqueToken, hashSecret } from "@/server/crypto";
import { accountLinkEmail, sendTrackedEmail } from "@/server/resend";

export const runtime = "nodejs";

const requestSchema = z.object({ email: z.email().transform((email) => email.toLowerCase()) });
const genericResponse = { message: "If that address has a Klipt purchase, a link is on its way." };

export async function POST(request: Request) {
  const body = await request.formData();
  const parsed = requestSchema.safeParse({ email: body.get("email") });
  if (!parsed.success) return NextResponse.json(genericResponse);
  try {
    const [customer] = await getDb()
      .select()
      .from(customers)
      .where(eq(customers.email, parsed.data.email))
      .limit(1);
    if (customer) {
      const token = await getDb().transaction(async (tx) => {
        await tx.execute(sql`select pg_advisory_xact_lock(hashtext(${customer.id}))`);
        const [recent] = await tx
          .select({ id: customerMagicLinks.id })
          .from(customerMagicLinks)
          .where(
            and(
              eq(customerMagicLinks.customerId, customer.id),
              gt(customerMagicLinks.createdAt, new Date(Date.now() - 15 * 60_000)),
            ),
          )
          .orderBy(desc(customerMagicLinks.createdAt))
          .limit(1);
        if (recent) return null;
        const nextToken = generateOpaqueToken();
        await tx.insert(customerMagicLinks).values({
          customerId: customer.id,
          tokenHash: hashSecret(nextToken),
          expiresAt: new Date(Date.now() + 15 * 60_000),
        });
        return nextToken;
      });
      if (!token) return NextResponse.json(genericResponse);
      const mail = accountLinkEmail(token);
      await sendTrackedEmail({
        customerId: customer.id,
        to: customer.email,
        kind: "account-link",
        ...mail,
      });
    }
  } catch (error) {
    console.error(
      "Account link request failed",
      error instanceof Error ? error.message : "Unknown error",
    );
  }
  return NextResponse.json(genericResponse);
}
