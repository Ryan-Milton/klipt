import "server-only";

import { GetObjectCommand, HeadObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";

import { env } from "@/server/env";

export async function createPrivateDownloadUrl(objectKey: string) {
  const config = env.r2();
  const client = createClient(config);
  return getSignedUrl(
    client,
    new GetObjectCommand({
      Bucket: config.R2_BUCKET,
      Key: objectKey,
      ResponseContentDisposition: 'attachment; filename="Klipt.dmg"',
    }),
    { expiresIn: 15 * 60 },
  );
}

export async function verifyPrivateArtifact(objectKey: string, sha256: string, sizeBytes: number) {
  const config = env.r2();
  const result = await createClient(config).send(
    new HeadObjectCommand({ Bucket: config.R2_BUCKET, Key: objectKey }),
  );
  return result.ContentLength === sizeBytes && result.Metadata?.sha256 === sha256;
}

function createClient(config: ReturnType<typeof env.r2>) {
  return new S3Client({
    region: "auto",
    endpoint: `https://${config.R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
    credentials: {
      accessKeyId: config.R2_ACCESS_KEY_ID,
      secretAccessKey: config.R2_SECRET_ACCESS_KEY,
    },
  });
}
