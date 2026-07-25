import type { Metadata } from "next";

import { PostHogProvider } from "@/components/posthog-provider";

import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL(process.env.NEXT_PUBLIC_APP_URL ?? "https://www.klipt.dev"),
  title: { default: "Klipt — Everything you copy, ready.", template: "%s · Klipt" },
  description: "A fast, private clipboard history and snippets app for Apple Silicon Macs.",
  openGraph: {
    title: "Klipt — Everything you copy, ready.",
    description: "Clipboard history and snippets for your Mac. US$5, once.",
    type: "website",
  },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>
        <PostHogProvider>{children}</PostHogProvider>
      </body>
    </html>
  );
}
