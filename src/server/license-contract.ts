import { z } from "zod";

export const activationRequestSchema = z.object({
  license_key: z.string().trim().min(20).max(100),
  installation_id: z.uuid(),
  device_model: z.string().trim().min(1).max(100),
  device_nickname: z.string().trim().min(1).max(100),
  app_version: z.string().trim().min(1).max(30),
  app_build: z.string().trim().min(1).max(30),
});

export const validationRequestSchema = z.object({
  license_key: z.string().trim().min(20).max(100),
  installation_id: z.uuid(),
});

type LicenseResult =
  | { status: "active"; activatedAt?: Date }
  | { status: "invalid" | "installation_mismatch" | "conflict" | "refunded" | "revoked" };

export function publicLicenseResult(result: LicenseResult) {
  switch (result.status) {
    case "active":
      return {
        body: {
          status: "active",
          ...(result.activatedAt ? { activated_at: result.activatedAt.toISOString() } : {}),
        },
        status: 200,
      };
    case "refunded":
      return {
        body: { status: "refunded", message: "This license was refunded." },
        status: 200,
      };
    case "revoked":
      return {
        body: { status: "revoked", message: "This license was revoked." },
        status: 200,
      };
    case "conflict":
      return {
        body: {
          status: "not_activated",
          code: "device_limit",
          message: "This license is already active on another Mac.",
        },
        status: 409,
      };
    case "installation_mismatch":
      return {
        body: {
          status: "not_activated",
          code: "installation_mismatch",
          message: "This license is not active on this Mac.",
        },
        status: 409,
      };
    case "invalid":
      return {
        body: {
          status: "not_activated",
          code: "invalid_key",
          message: "The licensing server did not recognize this key.",
        },
        status: 404,
      };
  }
}
