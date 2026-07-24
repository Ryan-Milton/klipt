import type { Metadata } from "next";

import { AccountRequest } from "@/components/account-request";
import { SiteFooter } from "@/components/site-footer";
import { SiteHeader } from "@/components/site-header";

export const metadata: Metadata = { title: "Customer Account" };

export default function AccountPage() {
  return (
    <>
      <SiteHeader />
      <main className="account shell">
        <div>
          <p className="eyebrow">
            <span />
            Purchase drawer
          </p>
          <h1>Your Klipt account.</h1>
          <p>
            Request a private, one-time link to view purchase status and masked license/device
            details. Links expire after 15 minutes.
          </p>
          <AccountRequest />
        </div>
        <aside>
          <b>What is not here</b>
          <p>
            For your security, the account page never reveals the full license key or creates a
            replacement installer after redemption.
          </p>
          <p>Need a purchase receipt? Paddle provides it as merchant of record.</p>
        </aside>
      </main>
      <SiteFooter />
    </>
  );
}
