# Sandbox pipeline

This runbook validates checkout, fulfillment, private download, installation,
and native activation without mixing sandbox commerce data into production.
Never configure the sandbox deployment with the production Neon database,
Paddle credentials, encryption key, release token, or installer bucket.

## Topology

| Component          | Sandbox boundary                                                  |
| ------------------ | ----------------------------------------------------------------- |
| Web and API        | `https://sandbox.klipt.dev` in the `klipt-sandbox` Vercel project |
| Payments           | Paddle sandbox product, price, client token, API key, and webhook |
| Database           | Separate Neon project or branch containing only sandbox data      |
| Installer          | Private `klipt-installers-sandbox` R2 bucket                      |
| Email              | Resend test delivery to an operator-controlled inbox              |
| Native app         | Developer ID build compiled for the sandbox licensing API         |
| Release automation | `Release Klipt Sandbox`, GitHub `Sandbox` environment             |

The sandbox app uses the production bundle ID so its signing, Keychain, and
system-permission behavior match production. Remove existing Klipt state before
the clean-install test and do not run production and sandbox copies together.
Its Sparkle feed points to `https://sandbox.klipt.dev/appcast.xml`, which is not
published by the sandbox workflow, so it cannot update into a production build.

## Vercel configuration

Configure these values in the Production environment of the isolated
`klipt-sandbox` project:

- `NEXT_PUBLIC_APP_URL=https://sandbox.klipt.dev`
- `NEXT_PUBLIC_PADDLE_ENVIRONMENT=sandbox`
- `NEXT_PUBLIC_PADDLE_CLIENT_TOKEN`
- `NEXT_PUBLIC_PADDLE_PRICE_ID`
- `PADDLE_API_BASE=https://sandbox-api.paddle.com`
- `PADDLE_API_KEY`
- `PADDLE_WEBHOOK_SECRET`
- `PADDLE_PRICE_ID`
- `DATABASE_URL`
- `LICENSE_ENCRYPTION_KEY`
- `R2_ACCOUNT_ID`
- `R2_ACCESS_KEY_ID`
- `R2_SECRET_ACCESS_KEY`
- `R2_BUCKET=klipt-installers-sandbox`
- `RESEND_API_KEY`
- `EMAIL_FROM`
- `RELEASE_PUBLISH_TOKEN`
- `CUSTOMER_SESSION_SECRET`

Admin OAuth and PostHog are optional for the core acceptance flow. If admin is
enabled, use a dedicated OAuth callback for the sandbox hostname.

## GitHub configuration

Repository variables:

- `SANDBOX_APP_URL=https://sandbox.klipt.dev`
- `R2_SANDBOX_PRIVATE_BUCKET=klipt-installers-sandbox`
- Existing `SPARKLE_PUBLIC_ED_KEY`

The `Sandbox` environment requires:

- Existing Apple signing/notarization repository secrets
- `R2_ACCOUNT_ID`
- `R2_SANDBOX_ACCESS_KEY_ID`
- `R2_SANDBOX_SECRET_ACCESS_KEY`
- `SANDBOX_RELEASE_PUBLISH_TOKEN`

The sandbox release token must match the isolated Vercel project. The sandbox
R2 credential must not have production bucket access.

## Provisioning

1. Add `sandbox.klipt.dev` to the isolated Vercel project.
2. Publish the required DNS record through Cloudflare and wait for TLS.
3. Apply Drizzle migrations through `0006` to the empty sandbox database.
4. Create the Paddle sandbox product and price.
5. Configure Paddle checkout for `sandbox.klipt.dev`.
6. Create a webhook for
   `https://sandbox.klipt.dev/api/paddle/webhook` with the same event families
   as production.
7. Create the private sandbox R2 bucket and bucket-scoped credentials.
8. Deploy `main` to the isolated Vercel project.
9. Dispatch `Release Klipt Sandbox` from `main`.
10. Verify one current sandbox release artifact before opening checkout.

If upload succeeds but registration fails, the workflow will refuse to reuse or
overwrite the immutable object. Inspect the failed run, then issue a new
sandbox build number after correcting the cause.

## Clean-state reset

The shared bundle ID means this reset removes both development and production
Klipt state for the current macOS account. Treat the operation as destructive.
If any existing state must be retained, stop and use a fresh macOS account
instead.

1. Quit Klipt and disable Launch at Login in Klipt or System Settings.
2. Confirm `~/Library/Application Support/Klipt` contains no data that must be
   retained. An archive without the matching Keychain encryption key is not a
   usable backup.
3. Remove `/Applications/Klipt.app` and `~/Library/Application Support/Klipt`.
4. Delete the `com.ryanmilton.Klipt` defaults domain.
5. Delete these exact generic-password items without printing their values:
   - service `com.ryanmilton.Klipt.installation`, account `installation-id`
   - service `com.ryanmilton.Klipt.license`, account `license-key`
   - service `com.ryanmilton.Klipt.local-storage`, account `encryption-key`
6. Run `tccutil reset Accessibility com.ryanmilton.Klipt`.
7. Confirm the app, Application Support directory, defaults domain, and all
   three Keychain items are absent before downloading the sandbox DMG.
8. Repeat this reset after sandbox acceptance and before installing the final
   production build.

## Payment tests

### Declined

1. Open the sandbox marketing page and click Buy.
2. Use Paddle's documented sandbox decline simulation.
3. Confirm checkout does not reach the success page.
4. Confirm no customer entitlement, transaction, license, grant, or email was
   created in Klipt.

### Authorized

1. Use Paddle's documented sandbox approval card and a controlled inbox.
2. Confirm the success page loads.
3. Confirm one processed completion webhook, customer, completed transaction,
   active license, unused grant, and accepted fulfillment email.
4. Replay the completion webhook and confirm those cardinalities do not change.

## Download and activation

1. Confirm the fulfillment email contains one license key and one Klipt link.
2. Open the link without consuming it, then submit the confirmation once.
3. Download `Klipt.dmg`; do not record the presigned R2 URL.
4. Confirm the original Klipt link cannot be redeemed again.
5. Verify the DMG and app with `hdiutil`, `stapler`, `spctl`, and `codesign`.
6. Install and launch normally with browser quarantine intact.
7. Confirm first launch is not activated, then activate with the emailed key.
8. Complete Accessibility onboarding and verify capture, search, paste, Launch
   at Login, and activation persistence after relaunch.
9. Refresh activation twice from the same installation and confirm it remains
   active.
10. Refund the sandbox transaction and confirm the next validation blocks
    licensed actions while leaving existing history readable and deletable.

## Production gate

Do not publish `1.0.0 (1)` until this runbook passes and any fixes are merged.
After the sandbox pass, dispatch `Release Klipt` from `main` and verify the
private DMG, public update ZIP, signed appcast, current production release row,
and notes-only GitHub Release before any live purchase.
