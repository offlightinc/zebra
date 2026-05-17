import {
  jsonResponse,
  withAuthedGmailApiRoute,
} from "../../../../services/gmail/routeHelpers";
import {
  runGmailWorkflow,
  syncRecentGmail,
} from "../../../../services/gmail/workflows";

export const dynamic = "force-dynamic";

export async function POST(request: Request): Promise<Response> {
  return withAuthedGmailApiRoute(
    request,
    "/api/gmail/sync",
    { "cmux.gmail.operation": "sync_recent" },
    "/api/gmail/sync POST failed",
    async ({ user }) => {
      const result = await runGmailWorkflow(syncRecentGmail({
        userId: user.id,
        request,
      }));
      return jsonResponse(result);
    },
  );
}
