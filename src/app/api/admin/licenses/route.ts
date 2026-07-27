import { NextResponse } from "next/server";
import { z } from "zod";

import { issueTestLicense } from "@/server/admin-licenses";
import { auth } from "@/server/auth";

export const runtime = "nodejs";

const issueSchema = z.object({
  email: z
    .email()
    .max(320)
    .transform((email) => email.toLowerCase()),
});

export async function POST(request: Request) {
  const requestUrl = new URL(request.url);
  if (request.headers.get("origin") !== requestUrl.origin) {
    return NextResponse.json({ error: "Invalid origin" }, { status: 403 });
  }
  const session = await auth();
  if (!session?.user.githubId) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  const parsed = issueSchema.safeParse(Object.fromEntries(await request.formData()));
  if (!parsed.success) {
    return NextResponse.redirect(
      new URL("/admin?result=Enter%20a%20valid%20email", request.url),
      303,
    );
  }
  try {
    await issueTestLicense(parsed.data.email, session.user.githubId);
    return NextResponse.redirect(new URL("/admin?result=Test%20license%20sent", request.url), 303);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Test license issuance failed";
    console.error("Admin test license issuance failed", message);
    return NextResponse.redirect(
      new URL(`/admin?result=${encodeURIComponent(message)}`, request.url),
      303,
    );
  }
}
