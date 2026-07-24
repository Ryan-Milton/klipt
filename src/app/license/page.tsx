import type { Metadata } from "next";
import { LegalPage } from "@/components/legal-page";

export const metadata: Metadata = { title: "License Agreement" };
export default function LicensePage() {
  return (
    <LegalPage
      eyebrow="Your copy"
      title="Klipt License Agreement."
      intro="Klipt is licensed, not sold. The source code and application remain proprietary to Ryan Milton."
      sections={[
        {
          title: "Grant",
          body: (
            <p>
              After payment, you receive a limited, personal, revocable, non-exclusive license to
              install and use Klipt on one Apple Silicon Mac that meets the system requirements.
            </p>
          ),
        },
        {
          title: "One permanent activation",
          body: (
            <p>
              The first Mac installation to activate the key is the licensed device. The activation
              cannot be transferred, reset, or deactivated. Keep the key and downloaded installer
              secure.
            </p>
          ),
        },
        {
          title: "Restrictions",
          body: (
            <p>
              You may not distribute, sublicense, rent, sell, share, modify, reverse engineer,
              circumvent license controls, or use Klipt source or assets without written permission,
              except where applicable law expressly permits.
            </p>
          ),
        },
        {
          title: "Termination",
          body: (
            <p>
              The license ends if the purchase is refunded or charged back, if the key is revoked
              for abuse, or if you materially breach this agreement. You must then stop using Klipt.
            </p>
          ),
        },
        {
          title: "Updates",
          body: (
            <p>
              Lifetime updates means updates released for this Klipt product during its supported
              life. It does not guarantee particular features, perpetual service operation, or
              compatibility with future hardware.
            </p>
          ),
        },
      ]}
    />
  );
}
