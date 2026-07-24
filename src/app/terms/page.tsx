import type { Metadata } from "next";
import { LegalPage } from "@/components/legal-page";

export const metadata: Metadata = { title: "Terms" };
export default function TermsPage() {
  return (
    <LegalPage
      eyebrow="The arrangement"
      title="Terms of sale and use."
      intro="These terms apply to the Klipt website and your purchase of Klipt for macOS."
      sections={[
        {
          title: "Seller and payment",
          body: (
            <p>
              Klipt is sold by Ryan Milton in the United States. Paddle is the merchant of record
              and handles checkout, tax, receipts, and currency conversion. The listed base price is
              US$5.
            </p>
          ),
        },
        {
          title: "What you receive",
          body: (
            <p>
              A purchase grants a personal license for one Apple Silicon Mac running macOS 26 or
              newer, with lifetime updates while Klipt remains offered. There is no trial or
              subscription.
            </p>
          ),
        },
        {
          title: "Activation and delivery",
          body: (
            <p>
              The first installation ID to activate a key permanently claims that license. A license
              cannot be transferred, deactivated, reset, or recovered. The initial installer token
              is one-use. It may be reissued only before redemption.
            </p>
          ),
        },
        {
          title: "Acceptable use",
          body: (
            <p>
              Do not share, resell, reverse engineer, bypass licensing, disrupt the service, or use
              Klipt unlawfully. The proprietary License Agreement provides additional restrictions.
            </p>
          ),
        },
        {
          title: "Availability and liability",
          body: (
            <p>
              Klipt is provided as available without a promise that it will meet every need. To the
              extent allowed by law, liability is limited to the amount paid. Nothing here limits
              rights that cannot legally be limited.
            </p>
          ),
        },
      ]}
    />
  );
}
