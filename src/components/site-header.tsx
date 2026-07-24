import Link from "next/link";

import { CheckoutButton } from "@/components/checkout-button";

export function SiteHeader() {
  return (
    <header className="site-header">
      <Link className="wordmark" href="/" aria-label="Klipt home">
        <span>K</span> Klipt
      </Link>
      <nav aria-label="Main navigation">
        <Link href="/#features">Why Klipt</Link>
        <Link href="/#privacy">Privacy</Link>
        <Link href="/changelog">Changelog</Link>
        <CheckoutButton compact />
      </nav>
    </header>
  );
}
