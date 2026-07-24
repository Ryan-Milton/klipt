"use client";

import posthog from "posthog-js";
import { usePathname } from "next/navigation";
import { useEffect, type ReactNode } from "react";

let initialized = false;

export function PostHogProvider({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  useEffect(() => {
    const key = process.env.NEXT_PUBLIC_POSTHOG_KEY;
    if (!key || initialized) return;
    posthog.init(key, {
      api_host: process.env.NEXT_PUBLIC_POSTHOG_HOST ?? "https://us.i.posthog.com",
      persistence: "memory",
      autocapture: false,
      capture_pageview: false,
      capture_pageleave: false,
      disable_session_recording: true,
      person_profiles: "never",
    });
    initialized = true;
  }, []);
  useEffect(() => {
    if (initialized) posthog.capture("page_viewed", { path: analyticsPath(pathname) });
  }, [pathname]);
  return children;
}

function analyticsPath(pathname: string) {
  if (pathname.startsWith("/account/") && pathname !== "/account/details") {
    return "/account/[token]";
  }
  if (pathname.startsWith("/download/")) return "/download/[token]";
  return pathname;
}

export function track(
  event: "checkout_started" | "support_opened",
  properties?: Record<string, string>,
) {
  if (initialized) posthog.capture(event, properties);
}
