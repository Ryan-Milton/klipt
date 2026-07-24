import { NextResponse } from "next/server";

import { validateLicense } from "@/server/licenses";
import { publicLicenseResult, validationRequestSchema } from "@/server/license-contract";

export const runtime = "nodejs";

export async function POST(request: Request) {
  const parsed = validationRequestSchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) return NextResponse.json({ status: "invalid_request" }, { status: 400 });
  try {
    const result = await validateLicense(parsed.data.license_key, parsed.data.installation_id);
    const response = publicLicenseResult(result);
    return NextResponse.json(response.body, { status: response.status });
  } catch (error) {
    console.error(
      "License validation unavailable",
      error instanceof Error ? error.message : "Unknown error",
    );
    return NextResponse.json(
      {
        status: "service_unavailable",
        message: "The license state is unknown. Do not treat this response as revocation.",
      },
      { status: 503 },
    );
  }
}
