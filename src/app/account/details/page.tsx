import type { Metadata } from "next";
import { desc, eq } from "drizzle-orm";
import { cookies } from "next/headers";
import Link from "next/link";

import { getDb } from "@/db/client";
import { activations, customers, downloadGrants, licenses, transactions } from "@/db/schema";
import { decryptLicenseKey, maskLicenseKey } from "@/server/crypto";
import { customerSessionCookie, readCustomerSession } from "@/server/customer-session";

export const metadata: Metadata = { title: "Purchase Details" };
export const dynamic = "force-dynamic";

function unavailable() {
  return (
    <main className="status-page shell">
      <div className="status-slip">
        <span className="status-mark">×</span>
        <h1>Account session expired.</h1>
        <p>Request another one-time link to view your Klipt purchases.</p>
        <Link className="button button-ink" href="/account">
          Request a new link
        </Link>
      </div>
    </main>
  );
}

export default async function AccountDetailsPage() {
  const cookieStore = await cookies();
  const customerId = readCustomerSession(cookieStore.get(customerSessionCookie)?.value);
  if (!customerId) return unavailable();
  const db = getDb();
  const records = await db
    .select({
      email: customers.email,
      status: licenses.status,
      encryptedKey: licenses.encryptedKey,
      licenseId: licenses.id,
      transactionId: transactions.paddleTransactionId,
      purchasedAt: transactions.occurredAt,
    })
    .from(customers)
    .innerJoin(licenses, eq(licenses.customerId, customers.id))
    .innerJoin(transactions, eq(transactions.id, licenses.transactionId))
    .where(eq(customers.id, customerId))
    .orderBy(desc(transactions.occurredAt));
  if (records.length === 0) return unavailable();
  const purchases = await Promise.all(
    records.map(async (record) => {
      const [[activation], [grant]] = await Promise.all([
        db.select().from(activations).where(eq(activations.licenseId, record.licenseId)).limit(1),
        db
          .select({ usedAt: downloadGrants.usedAt })
          .from(downloadGrants)
          .where(eq(downloadGrants.licenseId, record.licenseId))
          .limit(1),
      ]);
      return { record, activation, grant };
    }),
  );
  return (
    <main className="account-detail shell">
      {purchases.map(({ record, activation, grant }) => (
        <section className="account-receipt" key={record.licenseId}>
          <p>KLIPT PURCHASE</p>
          <h1>{record.status}</h1>
          <dl>
            <dt>Purchase email</dt>
            <dd>{record.email.replace(/^(.{2}).*(@.*)$/, "$1••••$2")}</dd>
            <dt>License</dt>
            <dd>
              <code>{maskLicenseKey(decryptLicenseKey(record.encryptedKey))}</code>
            </dd>
            <dt>Transaction</dt>
            <dd>{record.transactionId}</dd>
            <dt>Purchased</dt>
            <dd>{record.purchasedAt.toLocaleDateString("en-US", { dateStyle: "medium" })}</dd>
            <dt>Mac</dt>
            <dd>
              {activation ? `${activation.nickname} · ${activation.deviceModel}` : "Not activated"}
            </dd>
            <dt>Installer grant</dt>
            <dd>
              {grant?.usedAt ? "Redeemed · no recovery" : "Unused · contact support to reissue"}
            </dd>
          </dl>
          <p className="fine-print">This session expires after 15 minutes.</p>
        </section>
      ))}
    </main>
  );
}
