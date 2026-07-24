import "server-only";

import { z } from "zod";

class ServiceConfigurationError extends Error {
  constructor(service: string, issues: string[]) {
    super(`${service} is not configured: ${issues.join(", ")}`);
    this.name = "ServiceConfigurationError";
  }
}

function parseService<T extends z.ZodRawShape>(service: string, shape: T) {
  const result = z.object(shape).safeParse(process.env);
  if (!result.success) {
    const issues = result.error.issues.map((issue) => `${issue.path.join(".")} ${issue.message}`);
    throw new ServiceConfigurationError(service, issues);
  }
  return result.data;
}

const required = z.string().trim().min(1);

export const env = {
  database: () => parseService("Neon", { DATABASE_URL: z.url() }),
  crypto: () =>
    parseService("license encryption", {
      LICENSE_ENCRYPTION_KEY: required.refine((value) => {
        try {
          return Buffer.from(value, "base64").length === 32;
        } catch {
          return false;
        }
      }, "must be a base64-encoded 32-byte key"),
    }),
  paddle: () =>
    parseService("Paddle", {
      PADDLE_API_KEY: required,
      PADDLE_PRICE_ID: required,
      PADDLE_API_BASE: z.url().default("https://api.paddle.com"),
    }),
  paddleWebhook: () => parseService("Paddle webhooks", { PADDLE_WEBHOOK_SECRET: required }),
  r2: () =>
    parseService("Cloudflare R2", {
      R2_ACCOUNT_ID: required,
      R2_ACCESS_KEY_ID: required,
      R2_SECRET_ACCESS_KEY: required,
      R2_BUCKET: required,
    }),
  resend: () =>
    parseService("Resend", {
      RESEND_API_KEY: required,
      EMAIL_FROM: required.default("Klipt <support@klipt.dev>"),
      NEXT_PUBLIC_APP_URL: z.url(),
    }),
  auth: () =>
    parseService("admin authentication", {
      AUTH_SECRET: required,
      AUTH_GITHUB_ID: required,
      AUTH_GITHUB_SECRET: required,
      ADMIN_GITHUB_USER_ID: z.string().regex(/^\d+$/, "must be a numeric GitHub user ID"),
    }),
  releasePublisher: () =>
    parseService("release publishing", {
      RELEASE_PUBLISH_TOKEN: z.string().min(32),
    }),
  customerSession: () =>
    parseService("customer sessions", {
      CUSTOMER_SESSION_SECRET: z.string().min(32),
    }),
  appUrl: () => parseService("application URL", { NEXT_PUBLIC_APP_URL: z.url() }),
};

export { ServiceConfigurationError };
