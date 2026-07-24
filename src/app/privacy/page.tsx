import type { Metadata } from "next";
import { LegalPage } from "@/components/legal-page";

export const metadata: Metadata = { title: "Privacy" };
export default function PrivacyPage() {
  return (
    <LegalPage
      eyebrow="Private papers"
      title="Privacy, without the fog."
      intro="Klipt is built to keep clipboard contents on your Mac and collect as little as practical."
      sections={[
        {
          title: "Clipboard data",
          body: (
            <p>
              Clipboard history and snippets are stored locally. We do not receive, sync, sell, or
              inspect clipboard contents.
            </p>
          ),
        },
        {
          title: "Purchases and licensing",
          body: (
            <p>
              Paddle processes payment as merchant of record. We receive purchase identifiers,
              status, amount, currency, and your purchase email. Activation records include a random
              installation ID, device model, nickname, and app version/build. Neon hosts these
              operational records.
            </p>
          ),
        },
        {
          title: "Website analytics",
          body: (
            <p>
              If enabled, PostHog receives explicit anonymous page-view and checkout-start events.
              Analytics are cookieless and memory-only; autocapture, replay, and person profiles are
              disabled. We do not send email addresses, license keys, clipboard data, or download
              tokens.
            </p>
          ),
        },
        {
          title: "Email and downloads",
          body: (
            <p>
              Resend delivers fulfillment and account emails. Cloudflare R2 stores the private
              installer. Download URLs expire after 15 minutes; initial grant tokens are one-use and
              stored only as hashes.
            </p>
          ),
        },
        {
          title: "Retention and requests",
          body: (
            <p>
              We retain licensing, transaction, security, and audit records as needed to operate
              Klipt and meet legal obligations. Contact support@klipt.dev for a privacy request.
              Some records must remain to prevent license abuse or document a purchase.
            </p>
          ),
        },
      ]}
    />
  );
}
