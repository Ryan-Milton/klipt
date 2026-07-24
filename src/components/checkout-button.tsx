"use client";

import { initializePaddle, type Paddle } from "@paddle/paddle-js";
import { useState } from "react";

import { track } from "@/components/posthog-provider";

let paddlePromise: Promise<Paddle | undefined> | undefined;

function paddleCheckout() {
  const token = process.env.NEXT_PUBLIC_PADDLE_CLIENT_TOKEN;
  if (!token) throw new Error("Paddle client token is not configured");
  paddlePromise ??= initializePaddle({
    token,
    environment:
      process.env.NEXT_PUBLIC_PADDLE_ENVIRONMENT === "sandbox" ? "sandbox" : "production",
  });
  return paddlePromise;
}

export function CheckoutButton({ compact = false }: { compact?: boolean }) {
  const [state, setState] = useState<"idle" | "loading" | "error">("idle");

  async function checkout() {
    setState("loading");
    track("checkout_started", { placement: compact ? "nav" : "price" });
    try {
      const priceId = process.env.NEXT_PUBLIC_PADDLE_PRICE_ID;
      if (!priceId) throw new Error("Paddle price is not configured");
      const paddle = await paddleCheckout();
      if (!paddle) throw new Error("Paddle checkout did not initialize");
      paddle.Checkout.open({
        items: [{ priceId, quantity: 1 }],
        customData: { product: "klipt_macos_lifetime" },
        settings: {
          successUrl: `${window.location.origin}/checkout/success`,
          showAddDiscounts: false,
          variant: "one-page",
        },
      });
      setState("idle");
    } catch {
      setState("error");
    }
  }

  return (
    <div className={compact ? "checkout-wrap compact" : "checkout-wrap"}>
      <button
        className="button button-primary"
        type="button"
        onClick={checkout}
        disabled={state === "loading"}
      >
        {state === "loading"
          ? "Opening Paddle…"
          : compact
            ? "Get Klipt · $5"
            : "Buy Klipt for US$5"}
      </button>
      {state === "error" && (
        <span className="form-error">Checkout is unavailable. Try again shortly.</span>
      )}
    </div>
  );
}
