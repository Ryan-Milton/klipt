import type { Metadata } from "next";
import Link from "next/link";

import { SiteFooter } from "@/components/site-footer";
import { SiteHeader } from "@/components/site-header";

export const metadata: Metadata = { title: "Support" };

export default function SupportPage() {
  return (
    <>
      <SiteHeader />
      <main className="support shell">
        <header>
          <p className="eyebrow">
            <span />A real inbox
          </p>
          <h1>How can we help?</h1>
          <p>
            Klipt support is handled by its maker. Include your macOS version, Mac model, and Klipt
            build when reporting a problem. Never email your full license key.
          </p>
        </header>
        <div className="support-slips">
          <article>
            <span>01</span>
            <h2>Something broken?</h2>
            <p>
              Tell us what happened and what you expected. A screen recording is welcome, but check
              it for private clipboard contents first.
            </p>
            <a
              className="button button-ink"
              href="mailto:support@klipt.dev?subject=Klipt%20support"
            >
              Email support
            </a>
          </article>
          <article>
            <span>02</span>
            <h2>Purchase question?</h2>
            <p>
              Use the purchase email and include your Paddle transaction ID. Installer reissue is
              available only while the first grant remains unused.
            </p>
            <Link className="text-link" href="/account">
              Open customer account →
            </Link>
          </article>
          <article>
            <span>03</span>
            <h2>Looking for a refund?</h2>
            <p>
              Requests are accepted for 14 days. Paddle completes payment reversals as merchant of
              record.
            </p>
            <Link className="text-link" href="/refund">
              Read the refund policy →
            </Link>
          </article>
        </div>
      </main>
      <SiteFooter />
    </>
  );
}
