import {
  jsonResponse,
  withAuthedGmailApiRoute,
} from "../../../../../services/gmail/routeHelpers";
import {
  runGmailWorkflow,
  startGmailOAuth,
} from "../../../../../services/gmail/workflows";

export const dynamic = "force-dynamic";

export async function POST(request: Request): Promise<Response> {
  return withAuthedGmailApiRoute(
    request,
    "/api/gmail/oauth/start",
    { "cmux.gmail.operation": "oauth_start" },
    "/api/gmail/oauth/start POST failed",
    async ({ user }) => {
      const result = await runGmailWorkflow(startGmailOAuth({
        userId: user.id,
        request,
      }));
      return jsonResponse(result);
    },
  );
}
