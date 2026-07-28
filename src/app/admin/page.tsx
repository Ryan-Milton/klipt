import type { Metadata } from "next";
import { desc, eq } from "drizzle-orm";

import { getDb } from "@/db/client";
import {
  activations,
  adminAudit,
  adminNotes,
  customers,
  downloadGrants,
  emailDeliveries,
  licenses,
  transactions,
  webhookEvents,
} from "@/db/schema";
import { auth, signIn, signOut } from "@/server/auth";
import { maskLicenseKey, decryptLicenseKey } from "@/server/crypto";

export const metadata: Metadata = { title: "Operations", robots: { index: false, follow: false } };
export const dynamic = "force-dynamic";

function formatDate(value: Date | null) {
  return value ? value.toLocaleString("en-US", { dateStyle: "short", timeStyle: "short" }) : "—";
}

export default async function AdminPage({
  searchParams,
}: {
  searchParams: Promise<{ result?: string }>;
}) {
  const session = await auth();
  if (!session?.user.githubId) {
    return (
      <main className="admin-login">
        <div>
          <span className="wordmark">
            <span>K</span> Klipt
          </span>
          <p>PRIVATE OPERATIONS</p>
          <h1>Ryan’s desk.</h1>
          <form
            action={async () => {
              "use server";
              await signIn("github", { redirectTo: "/admin" });
            }}
          >
            <button className="button button-ink">Sign in with GitHub</button>
          </form>
        </div>
      </main>
    );
  }
  const db = getDb();
  const [
    licenseRows,
    transactionRows,
    activationRows,
    grantRows,
    webhookRows,
    emailRows,
    noteRows,
    auditRows,
  ] = await Promise.all([
    db
      .select({
        id: licenses.id,
        status: licenses.status,
        encryptedKey: licenses.encryptedKey,
        origin: licenses.origin,
        email: customers.email,
        createdAt: licenses.createdAt,
        revokedReason: licenses.revokedReason,
      })
      .from(licenses)
      .innerJoin(customers, eq(customers.id, licenses.customerId))
      .orderBy(desc(licenses.createdAt))
      .limit(30),
    db
      .select({
        id: transactions.paddleTransactionId,
        status: transactions.status,
        email: customers.email,
        total: transactions.totalMinor,
        currency: transactions.currencyCode,
        occurredAt: transactions.occurredAt,
      })
      .from(transactions)
      .innerJoin(customers, eq(customers.id, transactions.customerId))
      .orderBy(desc(transactions.occurredAt))
      .limit(30),
    db.select().from(activations).orderBy(desc(activations.createdAt)).limit(30),
    db.select().from(downloadGrants).orderBy(desc(downloadGrants.createdAt)).limit(30),
    db.select().from(webhookEvents).orderBy(desc(webhookEvents.createdAt)).limit(30),
    db.select().from(emailDeliveries).orderBy(desc(emailDeliveries.createdAt)).limit(30),
    db.select().from(adminNotes).orderBy(desc(adminNotes.createdAt)).limit(30),
    db.select().from(adminAudit).orderBy(desc(adminAudit.createdAt)).limit(50),
  ]);
  const { result } = await searchParams;
  return (
    <main className="admin">
      <header>
        <span className="wordmark">
          <span>K</span> Klipt Ops
        </span>
        <div>
          <span>GitHub ID {session.user.githubId}</span>
          <form
            action={async () => {
              "use server";
              await signOut({ redirectTo: "/" });
            }}
          >
            <button>Sign out</button>
          </form>
        </div>
      </header>
      {result && (
        <p className="admin-result" role="status">
          {result}
        </p>
      )}
      <nav>
        <a href="#issue">Issue</a>
        <a href="#licenses">Licenses</a>
        <a href="#transactions">Transactions</a>
        <a href="#webhooks">Webhooks</a>
        <a href="#delivery">Delivery</a>
        <a href="#audit">Audit</a>
      </nav>
      <section className="admin-issue" id="issue">
        <div>
          <p>TEST CREW / DIRECT ACCESS</p>
          <h1>Issue a test license.</h1>
          <p>
            Creates a complimentary one-Mac license and emails a one-use installer link. Existing
            test users should use Reissue + email on their license instead.
          </p>
        </div>
        <form action="/api/admin/licenses" method="post">
          <label htmlFor="test-license-email">Tester email</label>
          <input
            id="test-license-email"
            name="email"
            type="email"
            autoComplete="email"
            placeholder="tester@example.com"
            required
          />
          <button>Issue license + email</button>
        </form>
      </section>
      <section id="licenses">
        <h1>
          Licenses <span>{licenseRows.length} recent</span>
        </h1>
        <div className="admin-grid">
          {licenseRows.map((license) => {
            const activation = activationRows.find((item) => item.licenseId === license.id);
            const grant = grantRows.find((item) => item.licenseId === license.id);
            return (
              <article key={license.id} className={`admin-license ${license.status}`}>
                <div>
                  <b>
                    {license.origin === "admin" ? "TEST" : "PURCHASE"} · {license.status}
                  </b>
                  <code>{maskLicenseKey(decryptLicenseKey(license.encryptedKey))}</code>
                </div>
                <p>
                  {license.email}
                  <br />
                  {activation
                    ? `${activation.nickname} · ${activation.deviceModel}`
                    : "Not activated"}
                  <br />
                  Grant:{" "}
                  {grant?.usedAt
                    ? `used ${formatDate(grant.usedAt)}`
                    : grant
                      ? "unused"
                      : "missing"}
                </p>
                {license.revokedReason && <p>Reason: {license.revokedReason}</p>}
                <div className="admin-actions">
                  {license.status === "active" && (
                    <form action="/api/admin/action" method="post">
                      <input type="hidden" name="action" value="revoke" />
                      <input type="hidden" name="licenseId" value={license.id} />
                      <input name="reason" placeholder="Revocation reason" required />
                      <button>Revoke</button>
                    </form>
                  )}
                  {license.status === "revoked" && (
                    <form action="/api/admin/action" method="post">
                      <input type="hidden" name="action" value="unrevoke" />
                      <input type="hidden" name="licenseId" value={license.id} />
                      <button>Unrevoke</button>
                    </form>
                  )}
                  {license.status === "active" && grant && !grant.usedAt && (
                    <form action="/api/admin/action" method="post">
                      <input type="hidden" name="action" value="resend" />
                      <input type="hidden" name="licenseId" value={license.id} />
                      <input type="hidden" name="grantTokenHash" value={grant.tokenHash} />
                      <button>Reissue + email</button>
                    </form>
                  )}
                  <form action="/api/admin/action" method="post">
                    <input type="hidden" name="action" value="note" />
                    <input type="hidden" name="licenseId" value={license.id} />
                    <input name="body" placeholder="Internal note" required />
                    <button>Add note</button>
                  </form>
                </div>
              </article>
            );
          })}
        </div>
      </section>
      <section id="transactions">
        <h2>Transactions</h2>
        <div className="admin-table">
          <div className="admin-row heading">
            <span>ID</span>
            <span>Customer</span>
            <span>Status</span>
            <span>Total</span>
            <span>Occurred</span>
          </div>
          {transactionRows.map((row) => (
            <div className="admin-row" key={row.id}>
              <code>{row.id}</code>
              <span>{row.email}</span>
              <b>{row.status}</b>
              <span>
                {row.total == null ? "—" : `${row.currency} ${(row.total / 100).toFixed(2)}`}
              </span>
              <span>{formatDate(row.occurredAt)}</span>
            </div>
          ))}
        </div>
      </section>
      <section id="webhooks">
        <h2>Webhook events</h2>
        <div className="admin-table">
          {webhookRows.map((row) => (
            <div className="admin-row webhook" key={row.id}>
              <code>{row.providerEventId}</code>
              <span>{row.eventType}</span>
              <b>{row.status}</b>
              <span>{row.lastError ?? formatDate(row.processedAt)}</span>
              {row.status === "failed" ? (
                <form action="/api/admin/action" method="post">
                  <input type="hidden" name="action" value="retry" />
                  <input type="hidden" name="webhookId" value={row.id} />
                  <button>Retry</button>
                </form>
              ) : (
                <span />
              )}
            </div>
          ))}
        </div>
      </section>
      <section id="delivery">
        <h2>Email and downloads</h2>
        <div className="admin-table">
          {emailRows.map((row) => (
            <div className="admin-row" key={row.id}>
              <span>{row.kind}</span>
              <span>{row.recipient}</span>
              <b>{row.status}</b>
              <span>{row.lastError ?? row.providerMessageId ?? "pending"}</span>
              <span>{formatDate(row.createdAt)}</span>
            </div>
          ))}
        </div>
      </section>
      <section>
        <h2>Internal notes</h2>
        {noteRows.map((note) => (
          <p className="admin-note" key={note.id}>
            <b>{note.authorGithubId}</b> · {formatDate(note.createdAt)} · {note.body}
          </p>
        ))}
      </section>
      <section id="audit">
        <h2>Mutation audit</h2>
        <div className="admin-table">
          {auditRows.map((row) => (
            <div className="admin-row" key={row.id}>
              <span>{row.actorGithubId}</span>
              <b>{row.action}</b>
              <span>{row.targetType}</span>
              <code>{row.targetId}</code>
              <span>{formatDate(row.createdAt)}</span>
            </div>
          ))}
        </div>
      </section>
    </main>
  );
}
