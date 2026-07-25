import { createHmac } from "node:crypto";
import { afterEach, describe, expect, it, vi } from "vitest";

import {
  getPaddleTransaction,
  isKliptTransaction,
  mapPaddleOutcome,
  sanitizePaddleEvent,
  verifyPaddleSignature,
} from "./paddle";

const originalPaddleEnv = {
  PADDLE_API_KEY: process.env.PADDLE_API_KEY,
  PADDLE_PRICE_ID: process.env.PADDLE_PRICE_ID,
  PADDLE_API_BASE: process.env.PADDLE_API_BASE,
};

afterEach(() => {
  vi.unstubAllGlobals();
  for (const [key, value] of Object.entries(originalPaddleEnv)) {
    if (value === undefined) delete process.env[key];
    else process.env[key] = value;
  }
});

describe("Paddle webhooks", () => {
  it("verifies a current raw-body signature", () => {
    const body = '{"event_id":"evt_1"}';
    const signature = createHmac("sha256", "secret").update(`1000:${body}`).digest("hex");
    expect(verifyPaddleSignature(body, `ts=1000;h1=${signature}`, "secret", 1000)).toBe(true);
    expect(verifyPaddleSignature(`${body} `, `ts=1000;h1=${signature}`, "secret", 1000)).toBe(
      false,
    );
  });

  it("rejects stale signatures", () => {
    const signature = createHmac("sha256", "secret").update("1000:{}").digest("hex");
    expect(verifyPaddleSignature("{}", `ts=1000;h1=${signature}`, "secret", 1400)).toBe(false);
  });

  it("maps only explicit fulfillment and adverse outcomes", () => {
    expect(mapPaddleOutcome("transaction.completed", {})).toBe("completed");
    expect(mapPaddleOutcome("adjustment.updated", { action: "refund", status: "approved" })).toBe(
      "refunded",
    );
    expect(
      mapPaddleOutcome("adjustment.updated", { action: "credit", status: "approved" }),
    ).toBeNull();
    expect(mapPaddleOutcome("transaction.updated", { status: "past_due" })).toBeNull();
    expect(
      mapPaddleOutcome("adjustment.updated", { action: "chargeback", status: "approved" }),
    ).toBe("disputed");
    expect(
      mapPaddleOutcome("adjustment.updated", {
        action: "chargeback_reverse",
        status: "approved",
      }),
    ).toBe("restored");
  });

  it("drops fields not needed for retry", () => {
    const event = sanitizePaddleEvent({
      event_id: "evt_1",
      event_type: "transaction.completed",
      occurred_at: "2026-01-01T00:00:00Z",
      data: {
        id: "txn_1",
        card_number: "secret",
        customer: { email: "a@example.com" },
        custom_data: { product: "klipt_macos_lifetime", private_note: "secret" },
        items: [{ price: { id: "pri_1", name: "Private internal name" } }],
      },
    });
    expect(JSON.stringify(event)).not.toContain("card_number");
    expect(JSON.stringify(event)).not.toContain("private_note");
    expect(event.data.custom_data).toEqual({ product: "klipt_macos_lifetime" });
    expect(event.data.items).toEqual([{ price_id: "pri_1" }]);
  });

  it("distinguishes Klipt transactions from other products in the shared account", () => {
    const transaction = {
      custom_data: { product: "klipt_macos_lifetime" },
      items: [{ price: { id: "pri_klipt" } }],
    };
    expect(isKliptTransaction(transaction, "pri_klipt")).toBe(true);
    expect(
      isKliptTransaction(
        {
          custom_data: { product: "knosys_lifetime" },
          items: [{ price: { id: "pri_knosys" } }],
        },
        "pri_klipt",
      ),
    ).toBe(false);
    expect(() => isKliptTransaction(transaction, "pri_knosys")).toThrow(
      "inconsistent Klipt product metadata",
    );
    expect(() => isKliptTransaction({ items: [{ price_id: "pri_klipt" }] }, "pri_klipt")).toThrow(
      "inconsistent Klipt product metadata",
    );
    expect(() => isKliptTransaction({ custom_data: null, items: [] }, "pri_klipt")).toThrow(
      "Paddle transaction has no items",
    );
  });

  it("loads an adjustment transaction for product classification", async () => {
    process.env.PADDLE_API_KEY = "pdl_test_key";
    process.env.PADDLE_PRICE_ID = "pri_klipt";
    process.env.PADDLE_API_BASE = "https://api.paddle.test";
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        data: {
          custom_data: { product: "klipt_macos_lifetime" },
          items: [{ price: { id: "pri_klipt" } }],
        },
      }),
    });
    vi.stubGlobal("fetch", fetchMock);

    const transaction = await getPaddleTransaction("txn_1");

    expect(isKliptTransaction(transaction, "pri_klipt")).toBe(true);
    expect(fetchMock).toHaveBeenCalledWith(
      "https://api.paddle.test/transactions/txn_1",
      expect.objectContaining({ cache: "no-store" }),
    );
  });

  it("retries classification when Paddle cannot load a transaction", async () => {
    process.env.PADDLE_API_KEY = "pdl_test_key";
    process.env.PADDLE_PRICE_ID = "pri_klipt";
    process.env.PADDLE_API_BASE = "https://api.paddle.test";
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: false, status: 503 }));

    await expect(getPaddleTransaction("txn_1")).rejects.toThrow(
      "Paddle transaction request failed (503)",
    );
  });
});
