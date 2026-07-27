import "server-only";

import { eq } from "drizzle-orm";
import { Resend } from "resend";

import { getDb } from "@/db/client";
import { emailDeliveries } from "@/db/schema";
import { env } from "@/server/env";

type Mail = {
  customerId?: string;
  to: string;
  subject: string;
  html: string;
  text: string;
  kind: "fulfillment" | "account-link";
  idempotencyKey?: string;
};

export async function sendTrackedEmail(mail: Mail) {
  const config = env.resend();
  const db = getDb();
  const [delivery] = await db
    .insert(emailDeliveries)
    .values({ customerId: mail.customerId, kind: mail.kind, recipient: mail.to })
    .returning({ id: emailDeliveries.id });
  try {
    const result = await new Resend(config.RESEND_API_KEY).emails.send(
      {
        from: config.EMAIL_FROM,
        to: mail.to,
        subject: mail.subject,
        html: mail.html,
        text: mail.text,
      },
      { idempotencyKey: mail.idempotencyKey },
    );
    if (result.error) throw new Error(result.error.message);
    await db
      .update(emailDeliveries)
      .set({ status: "sent", providerMessageId: result.data?.id, updatedAt: new Date() })
      .where(eq(emailDeliveries.id, delivery.id));
  } catch (error) {
    await db
      .update(emailDeliveries)
      .set({
        status: "failed",
        lastError: error instanceof Error ? error.message.slice(0, 500) : "Unknown mail failure",
        updatedAt: new Date(),
      })
      .where(eq(emailDeliveries.id, delivery.id));
    throw error;
  }
}

export function fulfillmentEmail(licenseKey: string, token: string) {
  const appUrl = env.resend().NEXT_PUBLIC_APP_URL;
  const downloadUrl = new URL(`/download/${encodeURIComponent(token)}`, appUrl).toString();
  const safeLicenseKey = licenseKey
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
  return {
    subject: "Your Klipt license and download",
    html: `<!doctype html>
<html lang="en">
  <body style="margin:0;background:#f5efd9;color:#20241f;font-family:'Avenir Next','SF Pro Rounded',Arial,sans-serif;">
    <div style="display:none;max-height:0;overflow:hidden;opacity:0;">Your Klipt license and one-use installer link are ready.</div>
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f5efd9;">
      <tr>
        <td align="center" style="padding:32px 16px;">
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:600px;">
            <tr>
              <td style="padding:0 0 18px;font-size:22px;font-weight:800;letter-spacing:-1px;">
                <span style="display:inline-block;margin-right:9px;padding:3px 9px;border:2px solid #20241f;border-radius:7px;background:#ff806d;box-shadow:2px 2px 0 #20241f;font-size:17px;">K</span>
                Klipt
              </td>
            </tr>
            <tr>
              <td style="border:2px solid #20241f;border-radius:6px;background:#fffaf0;box-shadow:7px 8px 0 rgba(32,36,31,0.16);">
                <table role="presentation" width="100%" cellspacing="0" cellpadding="0">
                  <tr>
                    <td style="padding:36px 36px 20px;">
                      <p style="margin:0 0 14px;font-family:'SFMono-Regular',Consolas,monospace;font-size:11px;font-weight:700;letter-spacing:1.5px;text-transform:uppercase;color:#63665d;">Purchase / Ready</p>
                      <h1 style="margin:0 0 18px;font-family:Georgia,serif;font-size:42px;line-height:1.05;font-weight:400;letter-spacing:-1.5px;">Everything you copy,<br>ready.</h1>
                      <p style="margin:0;font-size:16px;line-height:1.65;color:#484d45;">Thanks for buying Klipt. Your one-Mac license and installer are below.</p>
                    </td>
                  </tr>
                  <tr>
                    <td style="padding:0 36px 22px;">
                      <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="border:2px solid #20241f;border-radius:5px;background:#c9e86c;">
                        <tr>
                          <td style="padding:19px 20px;">
                            <p style="margin:0 0 8px;font-family:'SFMono-Regular',Consolas,monospace;font-size:10px;font-weight:700;letter-spacing:1.4px;text-transform:uppercase;">Klipt license key</p>
                            <p style="margin:0;font-family:'SFMono-Regular',Consolas,monospace;font-size:17px;font-weight:700;line-height:1.5;word-break:break-all;">${safeLicenseKey}</p>
                          </td>
                        </tr>
                      </table>
                    </td>
                  </tr>
                  <tr>
                    <td style="padding:0 36px 26px;">
                      <a href="${downloadUrl}" style="display:inline-block;padding:14px 22px;border:2px solid #20241f;border-radius:5px;background:#ff806d;color:#20241f;box-shadow:4px 4px 0 #20241f;font-size:15px;font-weight:800;text-decoration:none;">Download Klipt once</a>
                    </td>
                  </tr>
                  <tr>
                    <td style="padding:0 36px 36px;">
                      <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="border-left:5px solid #70d9e7;background:#eef9f7;">
                        <tr>
                          <td style="padding:14px 16px;font-size:13px;line-height:1.6;color:#484d45;"><strong style="color:#20241f;">Keep both safe.</strong> The installer link works once. One license activates one Mac and cannot be transferred or recovered after installer redemption.</td>
                        </tr>
                      </table>
                    </td>
                  </tr>
                </table>
              </td>
            </tr>
            <tr>
              <td style="padding:22px 8px 0;font-size:12px;line-height:1.6;color:#63665d;">
                Klipt for Mac &middot; One-time purchase &middot; Lifetime updates<br>
                Need help? <a href="${appUrl}/support" style="color:#20241f;font-weight:700;">Visit Klipt support</a>.
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
  </body>
</html>`,
    text: `Everything you copy, ready.

Thanks for buying Klipt. Your one-Mac license key:

${licenseKey}

Download Klipt once:
${downloadUrl}

Keep both safe. The installer link works once. One license activates one Mac and cannot be transferred or recovered after installer redemption.

Klipt support: ${appUrl}/support`,
  };
}

export function accountLinkEmail(token: string) {
  const appUrl = env.resend().NEXT_PUBLIC_APP_URL;
  return {
    subject: "Your Klipt account link",
    html: `<p><a href="${appUrl}/account/${token}">Open your Klipt purchase</a></p><p>This one-time link expires in 15 minutes. It does not provide a new installer download.</p>`,
    text: `Open your Klipt purchase: ${appUrl}/account/${token}\n\nThis one-time link expires in 15 minutes. It does not provide a new installer download.`,
  };
}
