import { SiteFooter } from "@/components/site-footer";
import { SiteHeader } from "@/components/site-header";

export type LegalSection = { title: string; body: React.ReactNode };

export function LegalPage({
  eyebrow,
  title,
  intro,
  sections,
}: {
  eyebrow: string;
  title: string;
  intro: string;
  sections: LegalSection[];
}) {
  return (
    <>
      <SiteHeader />
      <main className="legal shell">
        <header>
          <p className="eyebrow">
            <span />
            {eyebrow}
          </p>
          <h1>{title}</h1>
          <p>{intro}</p>
          <small>Effective July 24, 2026</small>
        </header>
        <div className="legal-paper">
          {sections.map((section) => (
            <section key={section.title}>
              <h2>{section.title}</h2>
              <div>{section.body}</div>
            </section>
          ))}
        </div>
      </main>
      <SiteFooter />
    </>
  );
}
