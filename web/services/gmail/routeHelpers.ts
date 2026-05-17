import { recordSpanError, withApiRouteSpan, type MaybeAttributes } from "../telemetry";
import { unauthorized, verifyRequest, type AuthedUser } from "../vms/auth";
import { jsonResponse, parseBearer } from "../vms/routeHelpers";
import {
  GmailAuthError,
  GmailConfigError,
  GmailDatabaseError,
  GmailNotConnectedError,
  GmailProviderError,
  isGmailWorkflowError,
} from "./errors";

export type AuthedGmailRouteContext = {
  readonly user: AuthedUser;
};

export async function withAuthedGmailApiRoute(
  request: Request,
  route: string,
  attributes: MaybeAttributes,
  failureLog: string,
  handler: (context: AuthedGmailRouteContext) => Promise<Response>,
): Promise<Response> {
  return withApiRouteSpan(
    request,
    route,
    { "cmux.subsystem": "gmail", ...attributes },
    async (span) => {
      try {
        const bearer = parseBearer(request);
        const user = await verifyRequest(request);
        if (!user) return unauthorized();
        if (requiresBrowserMutationProtection(request.method, bearer) && !browserMutationOriginAllowed(request)) {
          return jsonResponse({ error: "forbidden" }, 403);
        }
        return await handler({ user });
      } catch (err) {
        recordSpanError(span, err);
        console.error(failureLog, err);
        if (isGmailWorkflowError(err)) return gmailErrorResponse(err);
        return jsonResponse({
          error: "gmail_internal_error",
          message: "Gmail request failed unexpectedly.",
        }, 500);
      }
    },
  );
}

export function gmailErrorResponse(err: unknown): Response {
  if (err instanceof GmailNotConnectedError) {
    return jsonResponse({
      error: "gmail_not_connected",
      message: "Gmail is not connected.",
    }, 409);
  }
  if (err instanceof GmailAuthError) {
    return jsonResponse({
      error: "gmail_oauth_invalid",
      message: err.message,
    }, 400);
  }
  if (err instanceof GmailConfigError) {
    return jsonResponse({
      error: "gmail_not_configured",
      message: err.message,
    }, 503);
  }
  if (err instanceof GmailProviderError) {
    return jsonResponse({
      error: "gmail_provider_error",
      message: err.message,
      operation: err.operation,
    }, err.status && err.status >= 400 && err.status < 500 ? 502 : 503);
  }
  if (err instanceof GmailDatabaseError) {
    return jsonResponse({
      error: "gmail_state_unavailable",
      message: "Gmail state is temporarily unavailable.",
      operation: err.operation,
    }, 503);
  }
  return jsonResponse({
    error: "gmail_internal_error",
    message: "Gmail request failed unexpectedly.",
  }, 500);
}

export { jsonResponse };

function requiresBrowserMutationProtection(method: string, bearer: unknown): boolean {
  if (bearer) return false;
  return method !== "GET" && method !== "HEAD" && method !== "OPTIONS";
}

function browserMutationOriginAllowed(request: Request): boolean {
  const origin = request.headers.get("origin");
  if (!origin) return false;
  const requestURL = new URL(request.url);
  return origin === `${requestURL.protocol}//${requestURL.host}`;
}
