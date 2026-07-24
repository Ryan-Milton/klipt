import "server-only";

import {
  createCipheriv,
  createDecipheriv,
  createHash,
  randomBytes,
  timingSafeEqual,
} from "node:crypto";

import { env } from "@/server/env";

const LICENSE_PREFIX = "KLIPT";

export function generateLicenseKey() {
  const body = randomBytes(24).toString("base64url").toUpperCase();
  return `${LICENSE_PREFIX}-${body.match(/.{1,8}/g)!.join("-")}`;
}

export function generateOpaqueToken() {
  return randomBytes(32).toString("base64url");
}

export function hashSecret(secret: string) {
  return createHash("sha256").update(secret, "utf8").digest("hex");
}

export function secretHashesEqual(leftHex: string, rightHex: string) {
  const left = Buffer.from(leftHex, "hex");
  const right = Buffer.from(rightHex, "hex");
  return left.length === right.length && timingSafeEqual(left, right);
}

export function encryptLicenseKey(licenseKey: string) {
  return encryptSecret(licenseKey);
}

export function encryptDownloadToken(token: string) {
  return encryptSecret(token);
}

function encryptSecret(value: string) {
  const key = Buffer.from(env.crypto().LICENSE_ENCRYPTION_KEY, "base64");
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", key, iv);
  const ciphertext = Buffer.concat([cipher.update(value, "utf8"), cipher.final()]);
  return [
    "v1",
    iv.toString("base64url"),
    cipher.getAuthTag().toString("base64url"),
    ciphertext.toString("base64url"),
  ].join(".");
}

export function decryptLicenseKey(value: string) {
  return decryptSecret(value);
}

export function decryptDownloadToken(value: string) {
  return decryptSecret(value);
}

function decryptSecret(value: string) {
  const [version, ivValue, tagValue, ciphertextValue] = value.split(".");
  if (version !== "v1" || !ivValue || !tagValue || !ciphertextValue) {
    throw new Error("Invalid encrypted license key");
  }
  const decipher = createDecipheriv(
    "aes-256-gcm",
    Buffer.from(env.crypto().LICENSE_ENCRYPTION_KEY, "base64"),
    Buffer.from(ivValue, "base64url"),
  );
  decipher.setAuthTag(Buffer.from(tagValue, "base64url"));
  return Buffer.concat([
    decipher.update(Buffer.from(ciphertextValue, "base64url")),
    decipher.final(),
  ]).toString("utf8");
}

export function maskLicenseKey(key: string) {
  return `${key.slice(0, 10)}••••••••${key.slice(-4)}`;
}
