import { afterEach, describe, expect, it } from "vitest";

import {
  decryptLicenseKey,
  encryptLicenseKey,
  generateLicenseKey,
  hashSecret,
  maskLicenseKey,
  secretHashesEqual,
} from "./crypto";

const originalKey = process.env.LICENSE_ENCRYPTION_KEY;

afterEach(() => {
  process.env.LICENSE_ENCRYPTION_KEY = originalKey;
});

describe("license cryptography", () => {
  it("generates a high-entropy formatted key", () => {
    expect(generateLicenseKey()).toMatch(/^KLIPT-[A-Z0-9_-]{8}(?:-[A-Z0-9_-]{8}){3}$/);
  });

  it("encrypts and authenticates a recoverable key", () => {
    process.env.LICENSE_ENCRYPTION_KEY = Buffer.alloc(32, 7).toString("base64");
    const encrypted = encryptLicenseKey("KLIPT-EXAMPLE");
    expect(encrypted).not.toContain("EXAMPLE");
    expect(decryptLicenseKey(encrypted)).toBe("KLIPT-EXAMPLE");
  });

  it("compares hashes and masks keys", () => {
    const hash = hashSecret("secret");
    expect(secretHashesEqual(hash, hashSecret("secret"))).toBe(true);
    expect(secretHashesEqual(hash, hashSecret("other"))).toBe(false);
    expect(maskLicenseKey("KLIPT-12345678-ABCDEFGH")).toBe("KLIPT-1234••••••••EFGH");
  });
});
