import { beforeEach, describe, expect, it } from "vitest";

import { createCustomerSession, readCustomerSession } from "@/server/customer-session";

describe("customer sessions", () => {
  beforeEach(() => {
    process.env.CUSTOMER_SESSION_SECRET = "test-session-secret-that-is-longer-than-32-characters";
  });

  it("accepts a signed unexpired session", () => {
    const customerId = "6c6ec211-a202-4cc5-aab4-1332cd28c15c";
    const session = createCustomerSession(customerId, 1_000);
    expect(readCustomerSession(session, 2_000)).toBe(customerId);
  });

  it("rejects tampering and expiration", () => {
    const session = createCustomerSession("6c6ec211-a202-4cc5-aab4-1332cd28c15c", 1_000);
    expect(readCustomerSession(`${session}x`, 2_000)).toBeNull();
    expect(readCustomerSession(session, 1_000 + 15 * 60_000)).toBeNull();
  });
});
