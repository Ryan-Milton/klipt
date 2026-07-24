import { and, eq, gt, isNull } from "drizzle-orm";
import { NextResponse } from "next/server";
import { z } from "zod";

import { getDb } from "@/db/client";
import { customerMagicLinks } from "@/db/schema";
import { hashSecret } from "@/server/crypto";
import { createCustomerSession, customerSessionCookie } from "@/server/customer-session";
import { env } from "@/server/env";

export const runtime = "nodejs";

const tokenSchema = z.string().min(32).max(200);

export async function POST(request: Request) {
  const requestUrl = new URL(request.url);
  if (request.headers.get("origin") !== requestUrl.origin) {
    return NextResponse.json({ error: "Invalid origin" }, { status: 403 });
  }
  try {
    env.customerSession();
  } catch {
    return NextResponse.json({ error: "Customer accounts are unavailable" }, { status: 503 });
  }
  const form = await request.formData();
  const parsed = tokenSchema.safeParse(form.get("token"));
  if (!parsed.success)
    return NextResponse.redirect(new URL("/account?state=invalid", request.url), 303);
  const [link] = await getDb()
    .update(customerMagicLinks)
    .set({ usedAt: new Date(), updatedAt: new Date() })
    .where(
      and(
        eq(customerMagicLinks.tokenHash, hashSecret(parsed.data)),
        isNull(customerMagicLinks.usedAt),
        gt(customerMagicLinks.expiresAt, new Date()),
      ),
    )
    .returning({ customerId: customerMagicLinks.customerId });
  if (!link) return NextResponse.redirect(new URL("/account?state=invalid", request.url), 303);

  const response = NextResponse.redirect(new URL("/account/details", request.url), 303);
  response.cookies.set(customerSessionCookie, createCustomerSession(link.customerId), {
    httpOnly: true,
    sameSite: "lax",
    secure: process.env.NODE_ENV === "production",
    path: "/account",
    maxAge: 15 * 60,
  });
  return response;
}
