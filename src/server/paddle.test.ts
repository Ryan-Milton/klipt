import { createHmac } from "node:crypto";
import { describe, expect, it } from "vitest";

import { mapPaddleOutcome, sanitizePaddleEvent, verifyPaddleSignature } from "./paddle";

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
        items: [{ price: { id: "pri_1", name: "Private internal name" } }],
      },
    });
    expect(JSON.stringify(event)).not.toContain("card_number");
    expect(event.data.items).toEqual([{ price_id: "pri_1" }]);
  });
});
