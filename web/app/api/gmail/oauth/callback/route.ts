import {
  gmailErrorResponse,
} from "../../../../../services/gmail/routeHelpers";
import {
  handleGmailOAuthCallback,
  runGmailWorkflow,
} from "../../../../../services/gmail/workflows";

export const dynamic = "force-dynamic";

export async function GET(request: Request): Promise<Response> {
  const url = new URL(request.url);
  const error = url.searchParams.get("error");
  if (error) {
    return htmlResponse("Gmail connection was canceled.");
  }
  const code = url.searchParams.get("code");
  const state = url.searchParams.get("state");
  if (!code || !state) {
    return htmlResponse("Gmail callback is missing required parameters.", 400);
  }

  try {
    const result = await runGmailWorkflow(handleGmailOAuthCallback({
      code,
      state,
      request,
    }));
    const message = result.backfillSucceeded
      ? `Gmail connected for ${escapeHTML(result.email)}. You can return to Zebra.`
      : `Gmail connected for ${escapeHTML(result.email)}, but the initial inbox sync failed. Return to Zebra and press the Gmail sync button to retry.`;
    return htmlResponse(message);
  } catch (err) {
    const response = gmailErrorResponse(err);
    if (response.headers.get("content-type")?.includes("application/json")) {
      const body = await response.json().catch(() => ({ message: "Gmail connection failed." })) as { message?: unknown };
      return htmlResponse(typeof body.message === "string" ? body.message : "Gmail connection failed.", response.status);
    }
    return response;
  }
}

function htmlResponse(message: string, status = 200): Response {
  const html = `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Gmail connection</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 48px; color: #111827; }
    main { max-width: 560px; }
    h1 { font-size: 22px; margin: 0 0 12px; }
    p { font-size: 15px; line-height: 1.5; color: #374151; }
  </style>
</head>
<body>
  <main>
    <h1>Gmail connection</h1>
    <p>${escapeHTML(message)}</p>
  </main>
</body>
</html>`;
  return new Response(html, {
    status,
    headers: { "content-type": "text/html; charset=utf-8" },
  });
}

function escapeHTML(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll("\"", "&quot;")
    .replaceAll("'", "&#039;");
}
