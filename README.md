# Klipt

Klipt is a native Apple Silicon clipboard history and snippet utility for macOS
26+, with its storefront, commerce, licensing, and release services in the same
repository.

## Web

The root Next.js application uses Drizzle with Neon, Paddle Billing, private
Cloudflare R2 downloads, Resend, GitHub OAuth, and optional cookieless PostHog.

```sh
pnpm install
cp .env.example .env.local
pnpm db:migrate
pnpm dev
```

Provider credentials are validated when their service is invoked, so tests and
production builds do not require live secrets.

```sh
pnpm format:check
pnpm lint
pnpm typecheck
pnpm test
pnpm build
```

Generate `LICENSE_ENCRYPTION_KEY`, `CUSTOMER_SESSION_SECRET`, and
`RELEASE_PUBLISH_TOKEN` with:

```sh
openssl rand -base64 32
openssl rand -base64 48
openssl rand -base64 48
```

Never rotate the license encryption key without re-encrypting existing license
records.

## macOS

Open `Klipt.xcodeproj`, or build from the command line:

```sh
xcodebuild -project Klipt.xcodeproj -scheme Klipt -destination 'platform=macOS' build
```

Klipt keeps clipboard history encrypted locally. Activation uses separate
Keychain items for the emailed key and random installation UUID. A previously
validated active installation remains usable during network failures, while a
cached refunded or revoked license stays blocked.

Release configuration:

- Bundle identifier: `com.ryanmilton.Klipt`
- Version/build: `1.0.0` (`1`)
- Deployment: macOS 26+, Apple Silicon only, hardened runtime, unsandboxed
- Updates: Sparkle 2 at `https://updates.klipt.dev/appcast.xml`

## Deployment

See `docs/launch-checklist.md` for provider configuration, secrets, database
migrations, Paddle notifications, R2 buckets, Developer ID signing,
notarization, and the release workflow.
