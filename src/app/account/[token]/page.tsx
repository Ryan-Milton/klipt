import type { Metadata } from "next";

export const metadata: Metadata = { title: "Open Purchase Details" };

export default async function AccountTokenPage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  return (
    <main className="status-page shell">
      <div className="status-slip">
        <span className="status-mark">K</span>
        <p className="eyebrow">Private purchase drawer</p>
        <h1>Open your Klipt account?</h1>
        <p>
          Continue to use this one-time link and view your masked license, purchase, device, and
          installer status. Automated email previews cannot complete this step.
        </p>
        <form action="/api/account/redeem" method="post">
          <input name="token" type="hidden" value={token} />
          <button className="button button-ink" type="submit">
            View purchase details
          </button>
        </form>
      </div>
    </main>
  );
}
