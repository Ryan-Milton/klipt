# Launch checklist

The application code builds without provider credentials. Production purchase,
fulfillment, activation, and release publishing require the following setup.

## 1. Git and Vercel

- Use pull requests into `main` for web, native, and release-infrastructure
  changes. The root web and Xcode projects intentionally share one repository.
- Create a Vercel project for `Ryan-Milton/klipt`, deploy `main`, and attach
  `klipt.dev` and `www.klipt.dev`.
- Copy every variable from `.env.example` into Vercel Production. Use separate
  Paddle, Neon, and Resend values for local/sandbox testing.
- Generate `AUTH_SECRET`, `CUSTOMER_SESSION_SECRET`,
  `LICENSE_ENCRYPTION_KEY`, and `RELEASE_PUBLISH_TOKEN` independently. Store
  durable backup copies of the encryption and Sparkle keys.

## 2. Neon

- Create development and production databases.
- Set the pooled production connection string as `DATABASE_URL` in Vercel.
- Run `pnpm db:migrate` against each database before its first deployment.
- Confirm exactly one `release_artifacts.is_current` row after the first signed
  release workflow completes.

## 3. Paddle

- Create one non-recurring Klipt product and a US$5 price. Paddle handles local
  currency conversion; do not add purchasing-power tiers.
- Create a Paddle.js client-side token and set the matching sandbox or live
  `NEXT_PUBLIC_PADDLE_CLIENT_TOKEN`, `NEXT_PUBLIC_PADDLE_PRICE_ID`, and
  `NEXT_PUBLIC_PADDLE_ENVIRONMENT` values in Vercel.
- Set the default payment-link domain and checkout approval for `klipt.dev`.
- Use `https://sandbox-api.paddle.com` for sandbox `PADDLE_API_BASE`, and
  `https://api.paddle.com` for production.
- Restrict the Paddle API key to customer read and transaction read permissions;
  no write permission is required.
- Set the webhook destination to `https://www.klipt.dev/api/paddle/webhook` and
  subscribe to transaction completion plus the refund, adjustment, dispute,
  and chargeback events available in the account.
- Confirm live payloads against the stored sanitized event view before launch.
  Duplicate deliveries are expected and are deduplicated by Paddle event ID.
- Run a sandbox purchase, duplicate webhook replay, refund, and dispute test.

## 4. Resend and PostHog

- Verify `klipt.dev` in Resend and publish the requested SPF and DKIM records.
- Set `EMAIL_FROM` to `Klipt <support@klipt.dev>` and verify replies arrive.
- Create a PostHog project only if analytics are wanted. Keep autocapture,
  session recording, and person profiles disabled. Klipt emits explicit,
  cookieless website events and no native telemetry.

## 5. Admin OAuth

- Create a GitHub OAuth app with callback
  `https://www.klipt.dev/api/auth/callback/github`.
- Set `ADMIN_GITHUB_USER_ID` to the numeric GitHub user ID for `Ryan-Milton`,
  not the username. All other accounts are rejected.
- Verify the admin action audit table records note, resend, retry, revoke, and
  restore attempts.

## 6. R2

- Create a private installer bucket and set it as `R2_BUCKET` in Vercel.
- Create a separate public updates bucket with custom domain
  `updates.klipt.dev` for Sparkle ZIP files and `appcast.xml`.
- Set `R2_PRIVATE_BUCKET` and `R2_UPDATES_BUCKET` as GitHub repository
  variables. Give GitHub Actions write access to both buckets; give Vercel
  read-only access to the private installer bucket.
- Keep installer objects private. The download route consumes one grant and
  returns a reusable 15-minute presigned R2 URL.

## 7. Apple and Sparkle

- Install or export the Developer ID Application certificate for team
  `A8S73HH5G6` as a password-protected PKCS#12 file.
- Create an App Store Connect API key authorized for notarization.
- Generate one Sparkle EdDSA keypair. Set the public key as the repository
  variable `SPARKLE_PUBLIC_ED_KEY`; never place the private key in source or in
  the app.
- Base64-encode the PKCS#12, App Store Connect `.p8`, and Sparkle private key
  before placing them in GitHub secrets.

Required GitHub repository variables:

- `SPARKLE_PUBLIC_ED_KEY`
- `R2_PRIVATE_BUCKET`
- `R2_UPDATES_BUCKET`

Required GitHub Actions secrets:

- `BUILD_CERTIFICATE_BASE64`
- `P12_PASSWORD`
- `KEYCHAIN_PASSWORD`
- `ASC_KEY_BASE64`
- `ASC_KEY_ID`
- `ASC_ISSUER_ID`
- `SPARKLE_PRIVATE_KEY_BASE64`
- `R2_ACCOUNT_ID`
- `R2_ACCESS_KEY_ID`
- `R2_SECRET_ACCESS_KEY`
- `RELEASE_PUBLISH_TOKEN`

Run the `Release Klipt` workflow manually with a semantic version and a
monotonically increasing build number. It tests, archives, signs, notarizes,
staples, verifies the Sparkle keypair, signs the archive and feed, uploads
immutable version/build artifacts, registers the private installer, publishes
the signed appcast, and creates public GitHub release notes without attaching
the paid DMG.

## 8. Final acceptance

- Buy in Paddle sandbox and verify one fulfillment email arrives.
- Redeem the initial link once and verify the resulting R2 URL works for 15
  minutes while the original Klipt link no longer works.
- Activate the same key twice on the same installation and verify idempotency.
- Confirm the key is rejected on a different installation UUID.
- Test startup and paste while offline after a successful validation.
- Refund and revoke test licenses and confirm capture stops while history stays
  readable and deletable.
- Install the notarized DMG on a clean Apple Silicon Mac and verify Gatekeeper,
  Accessibility onboarding, Launch at Login, activation, and Sparkle update UI.
