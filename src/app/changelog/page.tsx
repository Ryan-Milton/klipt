import type { Metadata } from "next";

import { SiteFooter } from "@/components/site-footer";
import { SiteHeader } from "@/components/site-header";

export const metadata: Metadata = { title: "Changelog" };

export default function ChangelogPage() {
  return (
    <>
      <SiteHeader />
      <main className="changelog shell">
        <header>
          <p className="eyebrow">
            <span />
            What changed
          </p>
          <h1>Fresh from the workbench.</h1>
          <p>Release notes will appear here when signed public builds ship.</p>
        </header>
        <article>
          <div>
            <b>COMING SOON</b>
            <time>Initial release</time>
          </div>
          <section>
            <h2>Klipt 1.0</h2>
            <p>
              The first production build is being prepared for Apple Silicon Macs running macOS 26
              and later.
            </p>
            <ul>
              <li>Searchable local clipboard history</li>
              <li>Reusable snippets</li>
              <li>Keyboard-first native panel</li>
              <li>One-Mac license activation</li>
            </ul>
          </section>
        </article>
      </main>
      <SiteFooter />
    </>
  );
}
