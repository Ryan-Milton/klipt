import { createHash, timingSafeEqual } from "node:crypto";

import { eq, sql } from "drizzle-orm";
import { NextResponse } from "next/server";
import { z } from "zod";

import { getDb } from "@/db/client";
import { releaseArtifacts } from "@/db/schema";
import { env } from "@/server/env";
import { verifyPrivateArtifact } from "@/server/r2";

export const runtime = "nodejs";

const releaseSchema = z.object({
  version: z.string().regex(/^\d+\.\d+\.\d+$/),
  build: z.string().regex(/^\d+$/),
  r2ObjectKey: z
    .string()
    .trim()
    .min(1)
    .max(500)
    .refine((value) => !value.startsWith("/") && !value.includes(".."), "invalid object key"),
  sha256: z.string().regex(/^[a-f0-9]{64}$/),
  sizeBytes: z.number().int().positive().safe(),
});

function authorized(request: Request) {
  const supplied = request.headers.get("authorization")?.replace(/^Bearer\s+/i, "") ?? "";
  const expected = env.releasePublisher().RELEASE_PUBLISH_TOKEN;
  const suppliedHash = createHash("sha256").update(supplied).digest();
  const expectedHash = createHash("sha256").update(expected).digest();
  return timingSafeEqual(suppliedHash, expectedHash);
}

export async function POST(request: Request) {
  try {
    if (!authorized(request)) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  } catch {
    return NextResponse.json({ error: "Release publishing is unavailable" }, { status: 503 });
  }

  const parsed = releaseSchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) return NextResponse.json({ error: "Invalid release" }, { status: 400 });

  try {
    if (
      !(await verifyPrivateArtifact(
        parsed.data.r2ObjectKey,
        parsed.data.sha256,
        parsed.data.sizeBytes,
      ))
    ) {
      return NextResponse.json({ error: "R2 artifact metadata does not match" }, { status: 409 });
    }
  } catch {
    return NextResponse.json({ error: "R2 artifact is unavailable" }, { status: 409 });
  }

  const db = getDb();
  let artifact: { id: string };
  try {
    artifact = await db.transaction(async (tx) => {
      await tx.execute(sql`select pg_advisory_xact_lock(1263299668)`);
      const [sameBuild] = await tx
        .select()
        .from(releaseArtifacts)
        .where(
          sql`${releaseArtifacts.version} = ${parsed.data.version} and ${releaseArtifacts.build} = ${parsed.data.build}`,
        )
        .limit(1);
      if (sameBuild) {
        const identical =
          sameBuild.r2ObjectKey === parsed.data.r2ObjectKey &&
          sameBuild.sha256 === parsed.data.sha256 &&
          sameBuild.sizeBytes === parsed.data.sizeBytes;
        if (!identical) throw new Error("Release identity already exists with different bytes");
        if (sameBuild.isCurrent) return { id: sameBuild.id };
      }

      const [current] = await tx
        .select()
        .from(releaseArtifacts)
        .where(eq(releaseArtifacts.isCurrent, true))
        .limit(1);
      if (current && Number(parsed.data.build) <= Number(current.build)) {
        throw new Error("Release build must increase monotonically");
      }
      if (current) {
        await tx
          .update(releaseArtifacts)
          .set({ isCurrent: false, updatedAt: new Date() })
          .where(eq(releaseArtifacts.id, current.id));
      }
      if (sameBuild) {
        const [promoted] = await tx
          .update(releaseArtifacts)
          .set({ isCurrent: true, updatedAt: new Date() })
          .where(eq(releaseArtifacts.id, sameBuild.id))
          .returning({ id: releaseArtifacts.id });
        return promoted;
      }
      const [created] = await tx
        .insert(releaseArtifacts)
        .values({ ...parsed.data, isCurrent: true })
        .returning({ id: releaseArtifacts.id });
      return created;
    });
  } catch (error) {
    return NextResponse.json(
      { error: error instanceof Error ? error.message : "Release registration failed" },
      { status: 409 },
    );
  }

  return NextResponse.json({ registered: true, artifactId: artifact.id });
}
