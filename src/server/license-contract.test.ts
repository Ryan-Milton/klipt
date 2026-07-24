import { describe, expect, it } from "vitest";

import {
  activationRequestSchema,
  publicLicenseResult,
  validationRequestSchema,
} from "@/server/license-contract";

const nativeRequest = {
  license_key: "KLIPT-12345678-12345678-12345678",
  installation_id: "6C6EC211-A202-4CC5-AAB4-1332CD28C15C",
  device_model: "Mac16,1",
  device_nickname: "Ryan's Mac",
  app_version: "1.0.0",
  app_build: "1",
};

describe("native license contract", () => {
  it("accepts the activation payload encoded by the macOS client", () => {
    expect(activationRequestSchema.parse(nativeRequest)).toEqual(nativeRequest);
    expect(validationRequestSchema.parse(nativeRequest)).toEqual({
      license_key: nativeRequest.license_key,
      installation_id: nativeRequest.installation_id,
    });
  });

  it("uses statuses understood by the macOS response mapper", () => {
    expect(publicLicenseResult({ status: "conflict" })).toMatchObject({
      body: { status: "not_activated", code: "device_limit" },
      status: 409,
    });
    expect(
      publicLicenseResult({ status: "active", activatedAt: new Date("2026-07-24T12:00:00Z") }),
    ).toEqual({
      body: { status: "active", activated_at: "2026-07-24T12:00:00.000Z" },
      status: 200,
    });
  });
});
