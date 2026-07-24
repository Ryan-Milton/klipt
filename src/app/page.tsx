import { CheckoutButton } from "@/components/checkout-button";
import { SiteFooter } from "@/components/site-footer";
import { SiteHeader } from "@/components/site-header";

const faqs = [
  ["Which Macs does Klipt support?", "Apple Silicon Macs running macOS 26 or newer."],
  [
    "Is there a trial?",
    "There is no free trial. Klipt is US$5 once with lifetime updates, and you can request a refund within 14 days. Paddle converts currency at checkout.",
  ],
  [
    "How many Macs can I use?",
    "One license activates one Mac. The first installation wins, and it cannot be transferred or deactivated.",
  ],
  [
    "Can you recover my installer?",
    "Your initial download link is one-use. Before it is used, support can reissue it. After redemption, we cannot recover the installer.",
  ],
  [
    "What happens offline?",
    "Your clipboard stays local. A network problem during license validation is never treated as a revoked license.",
  ],
];

function TickerCopy({ hidden = false }: { hidden?: boolean }) {
  return (
    <span className="ticker-copy" aria-hidden={hidden || undefined}>
      PASTE FASTER <b>✦</b> STAYS ON YOUR MAC <b>✦</b> NO SUBSCRIPTION <b>✦</b> PASTE FASTER{" "}
      <b>✦</b> STAYS ON YOUR MAC
    </span>
  );
}

function ProductPreview() {
  return (
    <figure
      className="product-preview"
      aria-label="Illustrated product preview of the Klipt clipboard window"
    >
      <div className="tape tape-one" />
      <div className="tape tape-two" />
      <div className="mac-window">
        <div className="window-bar">
          <i />
          <i />
          <i />
          <span>Klipt</span>
          <kbd>⌃ ⌥ V</kbd>
        </div>
        <div className="clip-search">
          ⌕ <span>Search everything you copied…</span>
        </div>
        <div className="clip-row selected">
          <b>Design handoff notes</b>
          <small>just now</small>
          <p>Warm cream, cyan label, less chrome…</p>
        </div>
        <div className="clip-row">
          <b>support@klipt.dev</b>
          <small>4m</small>
          <p>Plain text · 17 characters</p>
        </div>
        <div className="clip-row">
          <b>Weekly standup</b>
          <small>12m</small>
          <p>Snippet · Work</p>
        </div>
      </div>
      <figcaption>Product interface preview · final app may evolve</figcaption>
      <span className="sticker">
        LOCAL
        <br />
        FIRST
      </span>
    </figure>
  );
}

export default function Home() {
  return (
    <>
      <SiteHeader />
      <main>
        <section className="hero shell">
          <div className="hero-copy">
            <p className="eyebrow">
              <span /> Made for macOS 26+
            </p>
            <h1>
              Everything you copy, <em>ready.</em>
            </h1>
            <p className="hero-lede">
              Klipt keeps clipboard history and your favorite snippets one quick shortcut away.
              Private, native, and out of your way.
            </p>
            <div className="hero-actions">
              <CheckoutButton />
              <span>
                One Mac · Lifetime updates
                <br />
                Apple Silicon only
              </span>
            </div>
          </div>
          <ProductPreview />
        </section>

        <section className="ticker" aria-label="Product highlights">
          <div className="ticker-track">
            <TickerCopy hidden />
            <TickerCopy />
            <TickerCopy hidden />
          </div>
        </section>

        <section className="demo shell" aria-labelledby="demo-title">
          <div className="section-label">01 / THE LITTLE THINGS</div>
          <div className="demo-copy">
            <h2 id="demo-title">
              A tidy drawer for
              <br />
              the things in your head.
            </h2>
            <p>
              Open Klipt, type a few letters, and paste. Pin the pieces you reuse. Your clipboard
              stops being a one-item balancing act.
            </p>
          </div>
          <ol className="paper-stack">
            <li>
              <span>⌘</span>
              <div>
                <b>Copy as usual</b>
                <p>Klipt quietly remembers in the background.</p>
              </div>
            </li>
            <li>
              <span>⇧</span>
              <div>
                <b>Open from anywhere</b>
                <p>A native panel appears over the app you’re using.</p>
              </div>
            </li>
            <li>
              <span>↵</span>
              <div>
                <b>Find, then paste</b>
                <p>Keyboard-first and finished in a breath.</p>
              </div>
            </li>
          </ol>
        </section>

        <section className="features shell" id="features" aria-labelledby="features-title">
          <div className="section-label">02 / DESK DRAWER</div>
          <h2 id="features-title">
            Useful by design.
            <br />
            <em>Quiet by default.</em>
          </h2>
          <div className="feature-notes">
            <article className="note pear">
              <span>HISTORY</span>
              <h3>Find that thing again.</h3>
              <p>Search recent text and links without breaking your flow.</p>
            </article>
            <article className="note cyan">
              <span>SNIPPETS</span>
              <h3>Keep the good bits.</h3>
              <p>Save addresses, replies, commands, or anything you type twice.</p>
            </article>
            <article className="note coral">
              <span>NATIVE</span>
              <h3>Feels like it belongs.</h3>
              <p>Fast launch, keyboard control, adaptive appearance, no browser shell.</p>
            </article>
          </div>
        </section>

        <section className="privacy-block" id="privacy">
          <div className="shell privacy-inner">
            <div className="privacy-seal">
              NO
              <br />
              PEEKING
            </div>
            <div>
              <div className="section-label">03 / PRIVATE PAPERS</div>
              <h2>
                Your clipboard is not
                <br />
                our business.
              </h2>
              <p>
                History and snippets live on your Mac. Klipt has no cloud sync and sends no
                clipboard contents to us. License checks contain only what is needed to validate
                your purchase and installation.
              </p>
              <a href="/privacy">Read the plain-language privacy policy →</a>
            </div>
          </div>
        </section>

        <section className="price shell" id="price">
          <div className="price-ticket">
            <span className="ticket-hole" />
            <p>KLIPT FOR MAC</p>
            <div className="price-number">
              <sup>US$</sup>5
            </div>
            <ul>
              <li>Pay once</li>
              <li>Lifetime updates</li>
              <li>One Apple Silicon Mac</li>
              <li>No subscription</li>
              <li>14-day refund window</li>
            </ul>
            <CheckoutButton />
            <small>
              Secure checkout and local currency conversion by Paddle, our merchant of record.
            </small>
          </div>
          <div className="price-copy">
            <div className="section-label">04 / FAIR AND SQUARE</div>
            <h2>
              One small price.
              <br />
              No recurring paperwork.
            </h2>
            <p>
              Fourteen days to request a refund. If refunded, the license stops working. Because a
              redeemed installer cannot be recovered or transferred, keep the DMG and license key
              safe.
            </p>
          </div>
        </section>

        <section className="faq shell">
          <div>
            <div className="section-label">05 / ASK AWAY</div>
            <h2>
              A few things
              <br />
              worth knowing.
            </h2>
          </div>
          <div>
            {faqs.map(([question, answer]) => (
              <details key={question}>
                <summary>
                  {question}
                  <span>+</span>
                </summary>
                <p>{answer}</p>
              </details>
            ))}
          </div>
        </section>
      </main>
      <SiteFooter />
    </>
  );
}
