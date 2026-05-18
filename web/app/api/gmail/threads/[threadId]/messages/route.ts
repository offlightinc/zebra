import {
  jsonResponse,
  withAuthedGmailApiRoute,
} from "../../../../../../services/gmail/routeHelpers";
import {
  getGmailThreadMessages,
  runGmailWorkflow,
} from "../../../../../../services/gmail/workflows";

export const dynamic = "force-dynamic";

type RouteContext = {
  readonly params: Promise<{ readonly threadId?: string }> | { readonly threadId?: string };
};

export async function GET(request: Request, context: RouteContext): Promise<Response> {
  const params = await context.params;
  const threadId = params.threadId?.trim();
  const forceRefresh = new URL(request.url).searchParams.get("refresh") === "1";
  if (!threadId) {
    return jsonResponse({
      error: "gmail_thread_id_required",
      message: "Gmail thread id is required.",
    }, 400);
  }

  return withAuthedGmailApiRoute(
    request,
    "/api/gmail/threads/[threadId]/messages",
    { "cmux.gmail.operation": "thread_messages" },
    "/api/gmail/threads/[threadId]/messages GET failed",
    async ({ user }) => {
      const detail = await runGmailWorkflow(getGmailThreadMessages({
        userId: user.id,
        request,
        threadId,
        forceRefresh,
      }));
      return jsonResponse(detail);
    },
  );
}
