import {
  jsonResponse,
  withAuthedGmailApiRoute,
} from "../../../../services/gmail/routeHelpers";
import {
  getGmailStatus,
  runGmailWorkflow,
} from "../../../../services/gmail/workflows";

export const dynamic = "force-dynamic";

export async function GET(request: Request): Promise<Response> {
  return withAuthedGmailApiRoute(
    request,
    "/api/gmail/status",
    { "cmux.gmail.operation": "status" },
    "/api/gmail/status GET failed",
    async ({ user }) => {
      const status = await runGmailWorkflow(getGmailStatus(user.id));
      return jsonResponse(status);
    },
  );
}
