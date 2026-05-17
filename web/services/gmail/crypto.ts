import { createCipheriv, createDecipheriv, createHash, randomBytes } from "node:crypto";
import { GmailConfigError } from "./errors";

const algorithm = "aes-256-gcm";
const version = "v1";

export function encryptGmailToken(plainText: string): string {
  const iv = randomBytes(12);
  const cipher = createCipheriv(algorithm, tokenEncryptionKey(), iv);
  const encrypted = Buffer.concat([
    cipher.update(plainText, "utf8"),
    cipher.final(),
  ]);
  const tag = cipher.getAuthTag();
  return [
    version,
    iv.toString("base64url"),
    tag.toString("base64url"),
    encrypted.toString("base64url"),
  ].join(".");
}

export function decryptGmailToken(value: string): string {
  const parts = value.split(".");
  if (parts.length !== 4 || parts[0] !== version) {
    throw new GmailConfigError("Stored Gmail token uses an unsupported encryption format.");
  }
  const [, ivRaw, tagRaw, encryptedRaw] = parts;
  const decipher = createDecipheriv(
    algorithm,
    tokenEncryptionKey(),
    Buffer.from(ivRaw, "base64url"),
  );
  decipher.setAuthTag(Buffer.from(tagRaw, "base64url"));
  const decrypted = Buffer.concat([
    decipher.update(Buffer.from(encryptedRaw, "base64url")),
    decipher.final(),
  ]);
  return decrypted.toString("utf8");
}

function tokenEncryptionKey(): Buffer {
  const configured = process.env.GMAIL_TOKEN_ENCRYPTION_KEY ?? process.env.CMUX_GMAIL_TOKEN_ENCRYPTION_KEY;
  const trimmed = configured?.trim();
  if (!trimmed) {
    throw new GmailConfigError("GMAIL_TOKEN_ENCRYPTION_KEY is required before storing Gmail OAuth tokens.");
  }
  return createHash("sha256").update(trimmed).digest();
}
