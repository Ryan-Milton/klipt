import { statSync, writeFileSync } from "node:fs";

const [version, build, downloadUrl, archivePath, outputPath] = process.argv.slice(2);
const signatureOutput = process.env.SPARKLE_SIGNATURE ?? "";

if (!version || !build || !downloadUrl || !archivePath || !outputPath) {
  throw new Error("Usage: create-appcast.mjs VERSION BUILD URL ARCHIVE OUTPUT");
}

const signature = signatureOutput.match(/sparkle:edSignature="([^"]+)"/)?.[1];
if (!signature) throw new Error("sign_update did not return an EdDSA signature");

const escapeXml = (value) =>
  value.replaceAll("&", "&amp;").replaceAll('"', "&quot;").replaceAll("<", "&lt;");
const size = statSync(archivePath).size;
const publishedAt = new Date().toUTCString();

const appcast = `<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Klipt Updates</title>
    <link>https://updates.klipt.dev/appcast.xml</link>
    <description>Klipt release updates</description>
    <language>en</language>
    <item>
      <title>Klipt ${escapeXml(version)}</title>
      <pubDate>${publishedAt}</pubDate>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
      <enclosure
        url="${escapeXml(downloadUrl)}"
        length="${size}"
        type="application/octet-stream"
        sparkle:version="${escapeXml(build)}"
        sparkle:shortVersionString="${escapeXml(version)}"
        sparkle:edSignature="${escapeXml(signature)}" />
    </item>
  </channel>
</rss>
`;

writeFileSync(outputPath, appcast, "utf8");
