import type { Metadata } from "next";
import Link from "next/link";

import { SiteFooter } from "@/components/site-footer";
import { SiteHeader } from "@/components/site-header";

export const metadata: Metadata = { title: "Purchase received" };

export default function CheckoutSuccessPage() {
  return (
    <>
      <SiteHeader />
      <main className="status-page shell">
        <div className="status-slip">
          <span className="status-mark">✓</span>
          <p className="eyebrow">
            <span />
            Paddle checkout complete
          </p>
          <h1>Check your inbox.</h1>
          <p>
            Paddle is confirming the transaction. Your Klipt license key and one-use installer link
            will arrive at the purchase email after confirmation.
          </p>
          <div className="status-callout">
            <b>Keep both safe.</b>
            <p>
              The first Mac to activate the key claims it permanently. The installer link can be
              redeemed only once.
            </p>
          </div>
          <Link className="text-link" href="/support">
            No email after a few minutes? Contact support →
          </Link>
        </div>
      </main>
      <SiteFooter />
    </>
  );
}
