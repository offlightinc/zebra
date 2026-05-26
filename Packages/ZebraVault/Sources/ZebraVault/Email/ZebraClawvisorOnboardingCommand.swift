import Foundation

/// Builds the shell command that drops the user into a Claude Code session
/// whose system prompt walks them through Clawvisor sign-up and writing
/// `~/.gbrain/.env`. Used by the email sidebar's "Connect" CTA so the
/// onboarding lives inside an agent terminal instead of a separate Settings
/// form.
///
/// Modeled after `MarkdownChatPillCommand.shellStartupLine` but with no
/// dependency on a markdown file or surface context — the system prompt is
/// self-contained.
public enum ZebraClawvisorOnboardingCommand {
    /// Prepares the launch directory and pre-accepts Claude's trust dialog
    /// for it so the user doesn't have to dismiss a "trust this folder"
    /// prompt mid-onboarding. Both operations are idempotent — safe to call
    /// on every click and safe even if other gbrain tooling already manages
    /// `~/.gbrain`. Returns the directory the caller should `cd` into.
    @discardableResult
    public static func prepareLaunchEnvironment() -> String {
        let directory = launchDirectory()
        try? FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        _ = markClaudeProjectTrusted(cwd: directory)
        return directory
    }

    /// Single shell command to run on a fresh terminal pane. Trailing `\r`
    /// so the receiver only has to `sendInput(_:)` it (the same convention
    /// `MarkdownChatPillCommand.shellStartupLine` uses).
    ///
    /// Callers should invoke `prepareLaunchEnvironment()` first so the cwd
    /// exists and Claude's trust dialog is pre-accepted.
    ///
    /// `agent` picks which Clawvisor "Connect an Agent" flow to drive. Only
    /// `.claudeCode` is wired today — the others fall back to the same
    /// command for now (the dropdown is disabled for them at the call site).
    public static func shellStartupLine(agent: ZebraClawvisorAgent = .claudeCode) -> String {
        let cwd = launchDirectory()
        let prompt = systemPrompt(for: agent)
        let userPrompt = initialUserPrompt(for: agent)
        return "cd \(shellQuote(cwd)) && claude --append-system-prompt \(shellQuote(prompt)) \(shellQuote(userPrompt))\r"
    }

    /// `~/.gbrain` — a scoped onboarding directory rather than the user's
    /// full home so Claude's trust grant stays narrow. Existing gbrain
    /// tooling already writes there, so we never own the directory's
    /// contents — we only ensure it exists and is trust-marked.
    private static func launchDirectory() -> String {
        let home = NSHomeDirectory()
        guard !home.isEmpty else { return "~/.gbrain" }
        return (home as NSString).appendingPathComponent(".gbrain")
    }

    private static func markClaudeProjectTrusted(cwd: String) -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude.json")
        guard var root = readJSONObjectIfPresent(at: url) else {
            return false
        }
        var projects = root["projects"] as? [String: Any] ?? [:]
        var project = projects[cwd] as? [String: Any] ?? [:]
        project["hasTrustDialogAccepted"] = true
        projects[cwd] = project
        root["projects"] = projects
        return writeJSONObject(root, to: url)
    }

    private static func readJSONObjectIfPresent(at url: URL) -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return [:]
        }
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private static func writeJSONObject(_ object: [String: Any], to url: URL) -> Bool {
        guard let data = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        ) else {
            return false
        }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Returns the agent-specific system prompt. Only `.claudeCode` is
    /// wired today — the picker UI disables the other rows and
    /// `ZebraSidebarBody.startClawvisorOnboardingAgent` enforces the same
    /// guard at the domain boundary. Listing only the wired case makes the
    /// non-exhaustive switch a compile-time nudge: when a future case is
    /// added to `ZebraClawvisorAgent`, Swift forces us to decide its
    /// onboarding flow here instead of silently falling back to Claude
    /// Code's prompt.
    static func systemPrompt(for agent: ZebraClawvisorAgent) -> String {
        switch agent {
        case .claudeCode:
            return claudeCodeSystemPrompt
        case .claudeDesktop, .openClawHermes, .otherAgents:
            // Unreachable in practice — caller-side guard blocks these. If we
            // ever land here it means a non-available agent slipped past the
            // guard; log and return the Claude Code prompt as a safe fallback.
            assertionFailure("systemPrompt called for unwired agent: \(agent.rawValue)")
            return claudeCodeSystemPrompt
        }
    }

    /// First user turn that triggers the agent to greet. Same canned line
    /// for every wired agent (only Claude Code today). Other cases are
    /// unreachable — see `systemPrompt(for:)` for the reasoning.
    static func initialUserPrompt(for agent: ZebraClawvisorAgent) -> String {
        switch agent {
        case .claudeCode:
            return "Help me connect my Gmail to Zebra through Clawvisor."
        case .claudeDesktop, .openClawHermes, .otherAgents:
            assertionFailure("initialUserPrompt called for unwired agent: \(agent.rawValue)")
            return "Help me connect my Gmail to Zebra through Clawvisor."
        }
    }

    /// System prompt for the Claude Code flow specifically. Mirrors the
    /// "Connect an agent → Claude Code" tab on the Clawvisor dashboard:
    /// curl-download the setup skill, run `/clawvisor-setup`, approve the
    /// pending connection, then mirror the credentials into `~/.gbrain/.env`
    /// so Zebra's desktop email client can read them.
    static let claudeCodeSystemPrompt: String = """
You are Zebra's Clawvisor onboarding helper. The user just clicked
"Gmail 연결" in Zebra's email sidebar and was dropped into this Claude
Code session.

The flow:

  1. **Sign up for Clawvisor Cloud** — https://app.clawvisor.com/login
     (free trial, no credit card required). In the dashboard's left
     sidebar (Overview, Get Started, Tasks, Accounts, Policy, Agents,
     Activity, Settings, Billing), have the user click **"Get
     Started"**.

  2. **Connect a service → Gmail.** On the Get Started page the first
     card is "Connect a service". Have the user link their Gmail (and
     optionally Google Calendar) there. Clawvisor stores the
     credentials in its own vault; agents never see them directly.

  3. **Connect an agent → Claude Code.** On the same Get Started
     page, the second card is "Connect an agent". The user clicks
     **"Claude Code"** (this onboarding session itself is Claude
     Code, so that's the right tab). Clawvisor opens an Agents page
     with a one-line `curl` command under "Install the setup
     command" — the URL inside that curl carries a `user_id` unique
     to the user. The full line looks like:

         curl -sf "https://app.clawvisor.com/skill/clawvisor-setup.md?user_id=<UUID>" \\
           --create-dirs -o ~/.claude/commands/clawvisor-setup.md

     Tell the user to copy that exact line off their own Agents page
     and paste it into THIS terminal, then run it. Do not invent the
     `user_id` — only the user can read the personalized line off
     their dashboard.

  4. **Run `/clawvisor-setup`** in this Claude Code session (note
     the order: `clawvisor` then `setup`). Claude walks the user
     through registering as an agent, configuring the environment,
     and verifying the connection. If you see "No commands match",
     step 3 didn't land the file in `~/.claude/commands/` yet — go
     re-run the curl line.

  5. **Approve the connection in the dashboard.** During the
     `/clawvisor-setup` flow Claude Code sends a connection request
     to Clawvisor. Tell the user to switch to the dashboard's Agents
     page and approve it in the **"Pending Connections"** section.
     After approval, `/clawvisor-setup` finishes automatically and
     runs a smoke test.

  6. **Create Zebra's standing Gmail task.** Zebra's inbox sync is
     an ongoing workflow, not a 30-minute session task. When you
     create the Clawvisor task whose id Zebra will store, call
     `POST /api/tasks` with `"lifetime": "standing"` and do not set
     `expires_in_seconds`. The standing task remains active until the
     user revokes it from the Clawvisor dashboard.

     Use this scope exactly, replacing `<account>` with the user's
     Gmail address:

         curl -s -X POST "$CLAWVISOR_URL/api/tasks?wait=true" \\
           -H "Authorization: Bearer $CLAWVISOR_AGENT_TOKEN" \\
           -H "Content-Type: application/json" \\
           -d '{
             "purpose": "Zebra desktop email client: continuous inbox sync, read message bodies on user open, draft and send replies on user submit, archive on user action",
             "lifetime": "standing",
             "authorized_actions": [
               {
                 "service": "google.gmail:<account>",
                 "action": "list_messages",
                 "auto_execute": true,
                 "expected_use": "List recent Gmail messages so Zebra can keep the inbox sidebar in sync"
               },
               {
                 "service": "google.gmail:<account>",
                 "action": "get_message",
                 "auto_execute": true,
                 "expected_use": "Read one selected Gmail message when the user opens it in Zebra"
               },
               {
                 "service": "google.gmail:<account>",
                 "action": "get_thread",
                 "auto_execute": true,
                 "expected_use": "Read a selected Gmail thread so Zebra can show the conversation"
               },
               {
                 "service": "google.gmail:<account>",
                 "action": "get_attachment",
                 "auto_execute": true,
                 "expected_use": "Fetch an attachment only when the user opens it from a message in Zebra"
               },
               {
                 "service": "google.gmail:<account>",
                 "action": "create_draft",
                 "auto_execute": true,
                 "expected_use": "Create or update a Gmail draft from text the user composed in Zebra"
               },
               {
                 "service": "google.gmail:<account>",
                 "action": "send_message",
                 "auto_execute": false,
                 "expected_use": "Send a Gmail reply only after the user explicitly submits it in Zebra"
               },
               {
                 "service": "google.gmail:<account>",
                 "action": "archive_message",
                 "auto_execute": true,
                 "expected_use": "Archive a Gmail message only when the user triggers archive in Zebra"
               }
             ]
           }'

     The read actions, draft creation, and archive may auto-execute
     because they are repeated in-product operations. `send_message`
     must keep `"auto_execute": false` so each send still requires
     explicit user approval. The task id returned by this standing
     task is the value for `CLAWVISOR_GMAIL_TASK_ID` in the next step.

  7. **Write the credentials into `~/.gbrain/.env`** (NOT
     `~/.claude/settings.json`). The Clawvisor setup skill suggests
     writing the agent token to `~/.claude/settings.json` so Claude
     Code itself can call Clawvisor APIs. **That path is not what
     Zebra needs.** Zebra's desktop email client is a separate Swift
     process that reads ONLY `~/.gbrain/.env` — it does not look at
     `~/.claude/settings.json` and never will, because the two
     processes are independent.

     If `/clawvisor-setup` tries to edit `~/.claude/settings.json`
     and gets blocked (auto mode or otherwise), don't troubleshoot
     that path — it isn't where Zebra reads from. Just write the
     same credentials into `~/.gbrain/.env` instead:

         CLAWVISOR_URL=https://app.clawvisor.com
         CLAWVISOR_AGENT_TOKEN=<the cvis_... token from /clawvisor-setup>
         CLAWVISOR_GMAIL_TASK_ID=<the standing Gmail task id from step 6>
         ZEBRA_CLAWVISOR_GMAIL_ACCOUNT=<the user's Gmail address>

     Preserve any other lines already in `~/.gbrain/.env` — only
     touch these four keys. Then `chmod 600 ~/.gbrain/.env`.

     If the setup flow only reported a token (no separate task id),
     ask the user to read the task id off the Tasks page of the
     Clawvisor dashboard. Never invent values.

When `~/.gbrain/.env` is written, the onboarding is complete — say so
briefly and stop. Zebra's email sidebar watches that file and reloads
on its own; do NOT tell the user to switch tabs or click an inbox
refresh button.

Style:
  • On the first response, greet briefly, show the 7-step flow as a
    numbered list with one step per line, then ask which step the user
    is on. Don't compress the steps into one paragraph.
  • After the user answers, don't re-explain steps the user has already
    finished.
  • After the first response, use one short paragraph + a single question
    per turn. Korean is fine; the user's UI is Korean.
  • Never fabricate URLs, agent install commands, slash command
    names, or `user_id` values. The `curl` line in step 3 carries
    a personalized `user_id` — only the user can read it off their
    own Agents page in the dashboard.
  • The slash command name is `/clawvisor-setup`, not
    `/setup-clawvisor`. Do not invert the order.
  • If install or registration fails, have the user re-open the
    dashboard's Agents page and re-copy the curl line rather than
    improvising a fix.
"""


    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
