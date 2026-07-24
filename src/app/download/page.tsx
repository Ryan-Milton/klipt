import type { Metadata } from "next";
import Link from "next/link";

import { SiteFooter } from "@/components/site-footer";
import { SiteHeader } from "@/components/site-header";

export const metadata: Metadata = { title: "Download" };

export default async function DownloadPage({
  searchParams,
}: {
  searchParams: Promise<{ state?: string }>;
}) {
  const { state } = await searchParams;
  return (
    <>
      <SiteHeader />
      <main className="status-page shell">
        <div className="status-slip">
          <span className="status-mark">{state === "error" ? "!" : "×"}</span>
          <p className="eyebrow">
            <span />
            One-use delivery
          </p>
          <h1>{state === "error" ? "Download interrupted." : "That link is unavailable."}</h1>
          <p>
            {state === "error"
              ? "The storage service could not prepare your private download. Contact support so we can inspect the redemption."
              : "The installer link was already redeemed or is not valid. For security, a redeemed grant cannot be recovered or replaced."}
          </p>
          <Link className="button button-ink" href="/support">
            Contact support
          </Link>
        </div>
      </main>
      <SiteFooter />
    </>
  );
}
