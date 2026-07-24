import type { Metadata } from "next";

export const metadata: Metadata = { title: "Download Klipt" };

export default async function DownloadTokenPage({
  params,
}: {
  params: Promise<{ token: string }>;
}) {
  const { token } = await params;
  return (
    <main className="status-page shell">
      <div className="status-slip">
        <span className="status-mark">↓</span>
        <p className="eyebrow">Single-use installer grant</p>
        <h1>Download Klipt?</h1>
        <p>
          Continue to consume this one-time link and create a private R2 download URL that remains
          usable for 15 minutes. Keep the downloaded DMG somewhere safe.
        </p>
        <form action="/api/download/redeem" method="post">
          <input name="token" type="hidden" value={token} />
          <button className="button button-ink" type="submit">
            Create private download
          </button>
        </form>
      </div>
    </main>
  );
}
