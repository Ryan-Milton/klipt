import type { Metadata } from "next";
import { LegalPage } from "@/components/legal-page";

export const metadata: Metadata = { title: "Refund Policy" };
export default function RefundPage() {
  return (
    <LegalPage
      eyebrow="Fair and square"
      title="14-day refund policy."
      intro="If Klipt is not right for you, request a refund within 14 days of purchase."
      sections={[
        {
          title: "How to request",
          body: (
            <p>
              Email support@klipt.dev from the purchase address with your Paddle transaction or
              receipt information. Paddle, as merchant of record, processes approved refunds.
            </p>
          ),
        },
        {
          title: "What happens next",
          body: (
            <p>
              A refunded, charged-back, or reversed transaction makes its license inactive. Refunds
              do not reset a device or create another download grant.
            </p>
          ),
        },
        {
          title: "Legal rights",
          body: (
            <p>
              This policy supplements any mandatory consumer rights that apply to you. Refund timing
              and currency conversion are handled by Paddle and your payment provider.
            </p>
          ),
        },
      ]}
    />
  );
}
