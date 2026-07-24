import Link from "next/link";

export function SiteFooter() {
  return (
    <footer className="site-footer">
      <div>
        <span className="wordmark">
          <span>K</span> Klipt
        </span>
        <p>A tiny clipboard companion for your Mac.</p>
      </div>
      <div className="footer-links">
        <Link href="/privacy">Privacy</Link>
        <Link href="/terms">Terms</Link>
        <Link href="/refund">Refunds</Link>
        <Link href="/license">License</Link>
        <Link href="/support">Support</Link>
        <Link href="/account">Customer account</Link>
      </div>
      <p>© 2026 Ryan Milton · United States</p>
    </footer>
  );
}
