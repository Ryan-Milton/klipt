import type { MetadataRoute } from "next";

export default function sitemap(): MetadataRoute.Sitemap {
  return [
    "",
    "/privacy",
    "/terms",
    "/refund",
    "/support",
    "/changelog",
    "/license",
    "/account",
  ].map((path) => ({
    url: `https://www.klipt.dev${path}`,
    lastModified: new Date("2026-07-24"),
  }));
}
