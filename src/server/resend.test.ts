import { afterEach, beforeEach, describe, expect, it } from "vitest";

import { fulfillmentEmail, testLicenseEmail } from "./resend";

const originalResendEnv = {
  RESEND_API_KEY: process.env.RESEND_API_KEY,
  EMAIL_FROM: process.env.EMAIL_FROM,
  NEXT_PUBLIC_APP_URL: process.env.NEXT_PUBLIC_APP_URL,
};

beforeEach(() => {
  process.env.RESEND_API_KEY = "re_test";
  process.env.EMAIL_FROM = "Klipt <support@klipt.dev>";
  process.env.NEXT_PUBLIC_APP_URL = "https://sandbox.klipt.dev";
});

afterEach(() => {
  for (const [key, value] of Object.entries(originalResendEnv)) {
    if (value === undefined) delete process.env[key];
    else process.env[key] = value;
  }
});

describe("fulfillmentEmail", () => {
  it("renders the branded license and one-use download in HTML and plain text", () => {
    const mail = fulfillmentEmail("KLIPT-TEST-KEY", "download-token");

    expect(mail.subject).toBe("Your Klipt license and download");
    expect(mail.html).toContain("Everything you copy,<br>ready.");
    expect(mail.html).toContain("background:#f5efd9");
    expect(mail.html).toContain("KLIPT-TEST-KEY");
    expect(mail.html).toContain('href="https://sandbox.klipt.dev/download/download-token"');
    expect(mail.text).toContain("KLIPT-TEST-KEY");
    expect(mail.text).toContain("https://sandbox.klipt.dev/download/download-token");
  });

  it("escapes the license key in HTML", () => {
    const mail = fulfillmentEmail('KLIPT-<unsafe>&"', "download-token");

    expect(mail.html).toContain("KLIPT-&lt;unsafe&gt;&amp;&quot;");
    expect(mail.html).not.toContain('KLIPT-<unsafe>&"');
  });
});

describe("testLicenseEmail", () => {
  it("uses distinct test-crew branding and the same protected artifacts", () => {
    const mail = testLicenseEmail("KLIPT-TEST-KEY", "download-token");

    expect(mail.subject).toBe("Your Klipt test license");
    expect(mail.html).toContain("Test crew / Access granted");
    expect(mail.html).toContain("You&rsquo;re on the<br>test crew.");
    expect(mail.html).toContain("background:#70d9e7");
    expect(mail.html).toContain("complimentary one-Mac license");
    expect(mail.html).toContain("KLIPT-TEST-KEY");
    expect(mail.html).toContain('href="https://sandbox.klipt.dev/download/download-token"');
    expect(mail.text).toContain("You're on the test crew.");
    expect(mail.text).toContain("KLIPT-TEST-KEY");
  });
});
