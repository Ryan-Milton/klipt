import { NextResponse } from "next/server";

import { activateLicense } from "@/server/licenses";
import { activationRequestSchema, publicLicenseResult } from "@/server/license-contract";

export const runtime = "nodejs";

export async function POST(request: Request) {
  const parsed = activationRequestSchema.safeParse(await request.json().catch(() => null));
  if (!parsed.success) return NextResponse.json({ status: "invalid_request" }, { status: 400 });
  try {
    const result = await activateLicense({
      key: parsed.data.license_key,
      installationId: parsed.data.installation_id,
      deviceModel: parsed.data.device_model,
      nickname: parsed.data.device_nickname,
      appVersion: parsed.data.app_version,
      appBuild: parsed.data.app_build,
    });
    const response = publicLicenseResult(result);
    return NextResponse.json(response.body, { status: response.status });
  } catch (error) {
    console.error(
      "License activation unavailable",
      error instanceof Error ? error.message : "Unknown error",
    );
    return NextResponse.json(
      { status: "service_unavailable", message: "Try again without changing activation state." },
      { status: 503 },
    );
  }
}
