import { and, eq, isNull } from "drizzle-orm";
import { NextResponse } from "next/server";
import { z } from "zod";

import { getDb } from "@/db/client";
import { downloadGrants, releaseArtifacts } from "@/db/schema";
import { hashSecret } from "@/server/crypto";
import { createPrivateDownloadUrl } from "@/server/r2";

export const runtime = "nodejs";

const tokenSchema = z.string().min(32).max(200);

export async function POST(request: Request) {
  const requestUrl = new URL(request.url);
  if (request.headers.get("origin") !== requestUrl.origin) {
    return NextResponse.json({ error: "Invalid origin" }, { status: 403 });
  }
  const form = await request.formData();
  const parsed = tokenSchema.safeParse(form.get("token"));
  if (!parsed.success)
    return NextResponse.redirect(new URL("/download?state=unavailable", request.url), 303);
  try {
    const db = getDb();
    const [candidate] = await db
      .select({ id: downloadGrants.id, objectKey: releaseArtifacts.r2ObjectKey })
      .from(downloadGrants)
      .innerJoin(releaseArtifacts, eq(releaseArtifacts.id, downloadGrants.artifactId))
      .where(
        and(eq(downloadGrants.tokenHash, hashSecret(parsed.data)), isNull(downloadGrants.usedAt)),
      )
      .limit(1);
    if (!candidate) {
      return NextResponse.redirect(new URL("/download?state=unavailable", request.url), 303);
    }
    const privateUrl = await createPrivateDownloadUrl(candidate.objectKey);
    const [consumed] = await db
      .update(downloadGrants)
      .set({ usedAt: new Date(), updatedAt: new Date() })
      .where(and(eq(downloadGrants.id, candidate.id), isNull(downloadGrants.usedAt)))
      .returning({ id: downloadGrants.id });
    if (!consumed) {
      return NextResponse.redirect(new URL("/download?state=unavailable", request.url), 303);
    }
    return NextResponse.redirect(privateUrl, 303);
  } catch (error) {
    console.error(
      "Download redemption failed",
      error instanceof Error ? error.message : "Unknown error",
    );
    return NextResponse.redirect(new URL("/download?state=error", request.url), 303);
  }
}
