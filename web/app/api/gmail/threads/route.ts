import {
  jsonResponse,
  withAuthedGmailApiRoute,
} from "../../../../services/gmail/routeHelpers";
import {
  listGmailThreadDTOs,
  runGmailWorkflow,
} from "../../../../services/gmail/workflows";

export const dynamic = "force-dynamic";

export async function GET(request: Request): Promise<Response> {
  return withAuthedGmailApiRoute(
    request,
    "/api/gmail/threads",
    { "cmux.gmail.operation": "list_threads" },
    "/api/gmail/threads GET failed",
    async ({ user }) => {
      const threads = await runGmailWorkflow(listGmailThreadDTOs(user.id));
      return jsonResponse({ threads });
    },
  );
}
