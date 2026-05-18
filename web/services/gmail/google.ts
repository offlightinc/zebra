import { createHash, randomBytes } from "node:crypto";
import { GmailConfigError, GmailProviderError } from "./errors";

const gmailReadonlyScope = "https://www.googleapis.com/auth/gmail.readonly";
const userinfoEmailScope = "https://www.googleapis.com/auth/userinfo.email";
const metadataHeaders = ["From", "Subject", "Date"];
const maxPlainTextBodyLength = 80_000;
const maxHtmlBodyLength = 400_000;

export type GmailOAuthConfig = {
  readonly clientId: string;
  readonly clientSecret: string;
  readonly redirectUri: string;
};

export type GmailPkcePair = {
  readonly codeVerifier: string;
  readonly codeChallenge: string;
};

export type GmailTokenResponse = {
  readonly accessToken: string;
  readonly refreshToken: string;
  readonly expiresAt: Date;
};

export type GmailProfile = {
  readonly emailAddress: string;
  readonly historyId?: string;
};

export type GmailListMessage = {
  readonly id: string;
  readonly threadId: string;
};

export type GmailMessage = {
  readonly id: string;
  readonly threadId: string;
  readonly labelIds?: readonly string[];
  readonly snippet?: string;
  readonly historyId?: string;
  readonly internalDate?: string;
  readonly payload?: GmailPayloadPart;
};

export type GmailThread = {
  readonly id: string;
  readonly historyId?: string;
  readonly messages: readonly GmailMessage[];
};

export type ParsedGmailMessage = {
  readonly messageId: string;
  readonly threadId: string;
  readonly subject: string;
  readonly snippet: string;
  readonly senderName: string;
  readonly senderEmail: string | null;
  readonly receivedAt: Date;
  readonly labelIds: readonly string[];
  readonly hasAttachment: boolean;
  readonly historyId: string | null;
};

export type ParsedGmailThreadMessage = {
  readonly messageId: string;
  readonly threadId: string;
  readonly internetMessageId: string | null;
  readonly subject: string | null;
  readonly snippet: string;
  readonly senderName: string | null;
  readonly senderEmail: string | null;
  readonly to: string | null;
  readonly cc: string | null;
  readonly receivedAt: Date | null;
  readonly internalDateMs: number | null;
  readonly labelIds: readonly string[];
  readonly isUnread: boolean;
  readonly isSent: boolean;
  readonly hasAttachment: boolean;
  readonly bodyText: string | null;
  readonly bodyHtml: string | null;
};

type GmailPayloadPart = {
  readonly filename?: string;
  readonly mimeType?: string;
  readonly body?: {
    readonly attachmentId?: string;
    readonly data?: string;
    readonly size?: number;
  };
  readonly headers?: readonly { readonly name?: string; readonly value?: string }[];
  readonly parts?: readonly GmailPayloadPart[];
};

export function gmailOAuthConfig(request: Request): GmailOAuthConfig {
  const clientId = process.env.GOOGLE_GMAIL_CLIENT_ID ?? process.env.GOOGLE_CLIENT_ID;
  const clientSecret = process.env.GOOGLE_GMAIL_CLIENT_SECRET ?? process.env.GOOGLE_CLIENT_SECRET;
  if (!clientId?.trim() || !clientSecret?.trim()) {
    throw new GmailConfigError("Google Gmail OAuth client credentials are not configured.");
  }
  return {
    clientId: clientId.trim(),
    clientSecret: clientSecret.trim(),
    redirectUri: gmailRedirectUri(request),
  };
}

export function gmailRedirectUri(request: Request): string {
  const override = process.env.CMUX_GMAIL_REDIRECT_URI?.trim();
  if (override) return override;
  return new URL("/api/gmail/oauth/callback", request.url).toString();
}

export function createPkcePair(): GmailPkcePair {
  const codeVerifier = randomBytes(48).toString("base64url");
  const codeChallenge = createHash("sha256").update(codeVerifier).digest("base64url");
  return { codeVerifier, codeChallenge };
}

export function createGmailAuthUrl(input: {
  readonly config: GmailOAuthConfig;
  readonly state: string;
  readonly codeChallenge: string;
}): string {
  const url = new URL("https://accounts.google.com/o/oauth2/v2/auth");
  url.searchParams.set("client_id", input.config.clientId);
  url.searchParams.set("redirect_uri", input.config.redirectUri);
  url.searchParams.set("response_type", "code");
  url.searchParams.set("scope", [gmailReadonlyScope, userinfoEmailScope].join(" "));
  url.searchParams.set("access_type", "offline");
  url.searchParams.set("prompt", "consent");
  url.searchParams.set("state", input.state);
  url.searchParams.set("code_challenge", input.codeChallenge);
  url.searchParams.set("code_challenge_method", "S256");
  return url.toString();
}

export async function exchangeGmailCode(input: {
  readonly config: GmailOAuthConfig;
  readonly code: string;
  readonly codeVerifier: string;
}): Promise<GmailTokenResponse> {
  const body = new URLSearchParams({
    client_id: input.config.clientId,
    client_secret: input.config.clientSecret,
    code: input.code,
    code_verifier: input.codeVerifier,
    grant_type: "authorization_code",
    redirect_uri: input.config.redirectUri,
  });
  const json = await googleTokenRequest("oauth_exchange", body);
  const accessToken = stringField(json, "access_token");
  const refreshToken = stringField(json, "refresh_token");
  return {
    accessToken,
    refreshToken,
    expiresAt: expiresAtFromTokenResponse(json),
  };
}

export async function refreshGmailAccessToken(input: {
  readonly config: GmailOAuthConfig;
  readonly refreshToken: string;
}): Promise<{ readonly accessToken: string; readonly expiresAt: Date }> {
  const body = new URLSearchParams({
    client_id: input.config.clientId,
    client_secret: input.config.clientSecret,
    grant_type: "refresh_token",
    refresh_token: input.refreshToken,
  });
  const json = await googleTokenRequest("oauth_refresh", body);
  return {
    accessToken: stringField(json, "access_token"),
    expiresAt: expiresAtFromTokenResponse(json),
  };
}

export async function fetchGmailProfile(accessToken: string): Promise<GmailProfile> {
  const json = await gmailGetJSON("profile", accessToken, "/gmail/v1/users/me/profile");
  return {
    emailAddress: stringField(json, "emailAddress"),
    historyId: optionalStringField(json, "historyId"),
  };
}

export async function listRecentInboxMessages(
  accessToken: string,
  maxResults = 50,
): Promise<readonly GmailListMessage[]> {
  const path = `/gmail/v1/users/me/messages?labelIds=INBOX&maxResults=${maxResults}`;
  const json = await gmailGetJSON("list_messages", accessToken, path);
  const rawMessages = Array.isArray(json.messages) ? json.messages : [];
  return rawMessages.flatMap((value): GmailListMessage[] => {
    if (!value || typeof value !== "object") return [];
    const id = optionalStringField(value, "id");
    const threadId = optionalStringField(value, "threadId");
    return id && threadId ? [{ id, threadId }] : [];
  });
}

export async function fetchGmailMessage(
  accessToken: string,
  messageId: string,
): Promise<GmailMessage> {
  const params = new URLSearchParams({ format: "metadata" });
  for (const header of metadataHeaders) params.append("metadataHeaders", header);
  const path = `/gmail/v1/users/me/messages/${encodeURIComponent(messageId)}?${params.toString()}`;
  const json = await gmailGetJSON("get_message", accessToken, path);
  const id = stringField(json, "id");
  const threadId = stringField(json, "threadId");
  return {
    id,
    threadId,
    labelIds: Array.isArray(json.labelIds) ? json.labelIds.filter((v): v is string => typeof v === "string") : [],
    snippet: optionalStringField(json, "snippet") ?? "",
    historyId: optionalStringField(json, "historyId"),
    internalDate: optionalStringField(json, "internalDate"),
    payload: payloadPart(json.payload),
  };
}

export async function fetchGmailThread(
  accessToken: string,
  threadId: string,
): Promise<GmailThread> {
  const params = new URLSearchParams({ format: "full" });
  const path = `/gmail/v1/users/me/threads/${encodeURIComponent(threadId)}?${params.toString()}`;
  const json = await gmailGetJSON("get_thread", accessToken, path);
  return {
    id: stringField(json, "id"),
    historyId: optionalStringField(json, "historyId"),
    messages: Array.isArray(json.messages)
      ? json.messages.flatMap((value): GmailMessage[] => {
          const parsed = gmailMessageFromJSON(value);
          return parsed ? [parsed] : [];
        })
      : [],
  };
}

export function parseGmailMessage(message: GmailMessage): ParsedGmailMessage {
  const headers = message.payload?.headers ?? [];
  const subject = headerValue(headers, "subject") ?? "(no subject)";
  const from = headerValue(headers, "from") ?? "";
  const sender = parseSender(from);
  const dateHeader = headerValue(headers, "date");
  const receivedAt = dateFromGmail(message.internalDate, dateHeader);
  return {
    messageId: message.id,
    threadId: message.threadId,
    subject,
    snippet: message.snippet ?? "",
    senderName: sender.name || sender.email || from || "Unknown",
    senderEmail: sender.email,
    receivedAt,
    labelIds: message.labelIds ?? [],
    hasAttachment: payloadHasAttachment(message.payload),
    historyId: message.historyId ?? null,
  };
}

export function parseGmailThreadMessages(thread: GmailThread): readonly ParsedGmailThreadMessage[] {
  return thread.messages.map(parseGmailThreadMessage);
}

function parseGmailThreadMessage(message: GmailMessage): ParsedGmailThreadMessage {
  const headers = message.payload?.headers ?? [];
  const subject = headerValue(headers, "subject");
  const from = headerValue(headers, "from") ?? "";
  const sender = parseSender(from);
  const dateHeader = headerValue(headers, "date");
  const receivedAt = dateFromGmailNullable(message.internalDate, dateHeader);
  const bodies = extractBodies(message.payload);
  const labels = message.labelIds ?? [];
  return {
    messageId: message.id,
    threadId: message.threadId,
    internetMessageId: headerValue(headers, "message-id"),
    subject,
    snippet: message.snippet ?? "",
    senderName: sender.name || sender.email || null,
    senderEmail: sender.email,
    to: headerValue(headers, "to"),
    cc: headerValue(headers, "cc"),
    receivedAt,
    internalDateMs: internalDateMsFromGmail(message.internalDate),
    labelIds: labels,
    isUnread: labels.includes("UNREAD"),
    isSent: labels.includes("SENT"),
    hasAttachment: payloadHasAttachment(message.payload),
    bodyText: bodies.bodyText,
    bodyHtml: bodies.bodyHtml,
  };
}

async function googleTokenRequest(operation: string, body: URLSearchParams): Promise<Record<string, unknown>> {
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body,
  });
  return googleJSONResponse(operation, response);
}

async function gmailGetJSON(
  operation: string,
  accessToken: string,
  path: string,
): Promise<Record<string, unknown>> {
  const response = await fetch(`https://gmail.googleapis.com${path}`, {
    headers: { authorization: `Bearer ${accessToken}` },
  });
  return googleJSONResponse(operation, response);
}

async function googleJSONResponse(operation: string, response: Response): Promise<Record<string, unknown>> {
  const text = await response.text();
  if (!response.ok) {
    throw new GmailProviderError({
      operation,
      status: response.status,
      message: `Google Gmail request failed (${response.status}).`,
      cause: text,
    });
  }
  try {
    const json = JSON.parse(text) as unknown;
    if (!json || typeof json !== "object") {
      throw new Error("response was not an object");
    }
    return json as Record<string, unknown>;
  } catch (cause) {
    throw new GmailProviderError({
      operation,
      message: "Google Gmail returned malformed JSON.",
      cause,
    });
  }
}

function expiresAtFromTokenResponse(json: Record<string, unknown>): Date {
  const expiresIn = typeof json.expires_in === "number" ? json.expires_in : 3600;
  return new Date(Date.now() + Math.max(60, expiresIn - 60) * 1000);
}

function payloadPart(value: unknown): GmailPayloadPart | undefined {
  if (!value || typeof value !== "object") return undefined;
  const obj = value as Record<string, unknown>;
  return {
    filename: optionalStringField(obj, "filename"),
    mimeType: optionalStringField(obj, "mimeType"),
    body: payloadBody(obj.body),
    headers: Array.isArray(obj.headers)
      ? obj.headers.flatMap((header): { name?: string; value?: string }[] => {
          if (!header || typeof header !== "object") return [];
          const raw = header as Record<string, unknown>;
          return [{ name: optionalStringField(raw, "name"), value: optionalStringField(raw, "value") }];
        })
      : [],
    parts: Array.isArray(obj.parts) ? obj.parts.flatMap((part) => {
      const parsed = payloadPart(part);
      return parsed ? [parsed] : [];
    }) : [],
  };
}

function gmailMessageFromJSON(value: unknown): GmailMessage | null {
  if (!value || typeof value !== "object") return null;
  const raw = value as Record<string, unknown>;
  const id = optionalStringField(raw, "id");
  const threadId = optionalStringField(raw, "threadId");
  if (!id || !threadId) return null;
  return {
    id,
    threadId,
    labelIds: Array.isArray(raw.labelIds) ? raw.labelIds.filter((v): v is string => typeof v === "string") : [],
    snippet: optionalStringField(raw, "snippet") ?? "",
    historyId: optionalStringField(raw, "historyId"),
    internalDate: optionalStringField(raw, "internalDate"),
    payload: payloadPart(raw.payload),
  };
}

function payloadBody(value: unknown): GmailPayloadPart["body"] {
  if (!value || typeof value !== "object") return undefined;
  const obj = value as Record<string, unknown>;
  const attachmentId = optionalStringField(obj, "attachmentId");
  const data = optionalStringField(obj, "data");
  const size = typeof obj.size === "number" ? obj.size : undefined;
  return { attachmentId, data, size };
}

function payloadHasAttachment(part: GmailPayloadPart | undefined): boolean {
  if (!part) return false;
  if (part.filename?.trim()) return true;
  const disposition = headerValue(part.headers ?? [], "content-disposition")?.toLowerCase() ?? "";
  if (disposition.includes("attachment")) return true;
  if (part.body?.attachmentId && !part.mimeType?.toLowerCase().startsWith("text/")) return true;
  return (part.parts ?? []).some(payloadHasAttachment);
}

function extractBodies(part: GmailPayloadPart | undefined): {
  readonly bodyText: string | null;
  readonly bodyHtml: string | null;
} {
  const textParts: string[] = [];
  const htmlParts: string[] = [];

  function visit(current: GmailPayloadPart | undefined): void {
    if (!current) return;
    const mimeType = current.mimeType?.toLowerCase() ?? "";
    const decoded = decodeGmailBodyData(current.body?.data);
    if (decoded) {
      if (mimeType === "text/plain") {
        textParts.push(decoded);
      } else if (mimeType === "text/html") {
        htmlParts.push(decoded);
      }
    }
    for (const child of current.parts ?? []) visit(child);
  }

  visit(part);
  const rawHtml = firstNonEmpty(htmlParts);
  const bodyHtml = rawHtml && looksLikeHTML(rawHtml) ? truncate(rawHtml, maxHtmlBodyLength) : null;
  const bodyText = firstNonEmpty(textParts)
    ?? (bodyHtml ? htmlToPlainText(bodyHtml) : null)
    ?? (rawHtml && !bodyHtml ? rawHtml : null);
  return {
    bodyText: bodyText ? truncate(bodyText, maxPlainTextBodyLength) : null,
    bodyHtml,
  };
}

function decodeGmailBodyData(data: string | undefined): string | null {
  if (!data) return null;
  try {
    const normalized = data.replace(/-/g, "+").replace(/_/g, "/");
    const padded = normalized.padEnd(normalized.length + ((4 - (normalized.length % 4)) % 4), "=");
    const decoded = Buffer.from(padded, "base64").toString("utf8");
    const trimmed = decoded.trim();
    return trimmed ? decoded : null;
  } catch {
    return null;
  }
}

function firstNonEmpty(values: readonly string[]): string | null {
  for (const value of values) {
    if (value.trim()) return value;
  }
  return null;
}

function looksLikeHTML(value: string): boolean {
  return /<\/?[a-z][\s\S]*>/i.test(value);
}

function htmlToPlainText(value: string): string {
  return value
    .replace(/<script\b[\s\S]*?<\/script>/gi, "")
    .replace(/<style\b[\s\S]*?<\/style>/gi, "")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/(p|div|li|tr|h[1-6])>/gi, "\n")
    .replace(/<[^>]+>/g, "")
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&quot;/gi, "\"")
    .replace(/&#39;/gi, "'")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function truncate(value: string, maxLength: number): string {
  return value.length > maxLength ? value.slice(0, maxLength) : value;
}

function headerValue(
  headers: readonly { readonly name?: string; readonly value?: string }[],
  name: string,
): string | null {
  const lower = name.toLowerCase();
  return headers.find((header) => header.name?.toLowerCase() === lower)?.value ?? null;
}

function parseSender(value: string): { readonly name: string; readonly email: string | null } {
  const trimmed = value.trim();
  const match = trimmed.match(/^(.*)<([^>]+)>$/);
  if (!match) {
    const emailOnly = trimmed.includes("@") ? trimmed : null;
    return { name: emailOnly ? trimmed.split("@")[0] : trimmed, email: emailOnly };
  }
  const name = match[1].trim().replace(/^"|"$/g, "");
  const email = match[2].trim();
  return { name, email };
}

function dateFromGmail(internalDate: string | undefined, dateHeader: string | null): Date {
  return dateFromGmailNullable(internalDate, dateHeader) ?? new Date();
}

function dateFromGmailNullable(internalDate: string | undefined, dateHeader: string | null): Date | null {
  const millis = internalDateMsFromGmail(internalDate);
  if (millis !== null) return new Date(millis);
  if (dateHeader) {
    const parsed = Date.parse(dateHeader);
    if (Number.isFinite(parsed)) return new Date(parsed);
  }
  return null;
}

function internalDateMsFromGmail(internalDate: string | undefined): number | null {
  if (!internalDate) return null;
  const millis = Number(internalDate);
  return Number.isSafeInteger(millis) && millis > 0 ? millis : null;
}

function stringField(value: Record<string, unknown>, key: string): string {
  const raw = value[key];
  if (typeof raw === "string" && raw.trim()) return raw.trim();
  throw new GmailProviderError({
    operation: "parse_response",
    message: `Google Gmail response was missing ${key}.`,
  });
}

function optionalStringField(value: unknown, key: string): string | undefined {
  if (!value || typeof value !== "object") return undefined;
  const raw = (value as Record<string, unknown>)[key];
  return typeof raw === "string" && raw.trim() ? raw.trim() : undefined;
}
