import common as runtime
from connectors import obsidian, agent_memory, notion, imessage, apple_notes, apple_reminders, gmail

_RUNTIME_BINDINGS = {
    obsidian: (
        "obsidian_playbook", "obsidian_step_prompt", "set_obsidian_row_state",
        "start_obsidian_from_next",
    ),
    agent_memory: (
        "agent_memory_available", "agent_memory_playbook", "agent_memory_readiness",
        "agent_memory_step_prompt", "set_agent_memory_row_state", "start_agent_memory_from_next",
    ),
    notion: (
        "notion_playbook", "notion_step_prompt", "set_notion_row_state", "start_notion_from_next",
    ),
    imessage: (
        "imessage_playbook", "imessage_run_state_with_command_path", "imessage_scope_summary",
        "imessage_step_prompt", "set_imessage_row_state", "start_imessage_from_next",
    ),
    apple_notes: (
        "apple_notes_install_memo", "apple_notes_playbook", "apple_notes_scope_summary",
        "apple_notes_step_prompt", "set_apple_notes_row_state", "start_apple_notes_from_next",
    ),
    apple_reminders: (
        "apple_reminders_brew_path", "apple_reminders_playbook", "apple_reminders_scope_summary",
        "apple_reminders_step_prompt", "apple_reminders_transition", "set_apple_reminders_row_state",
        "start_apple_reminders_from_next",
    ),
    gmail: ("gmail_readiness", "gmail_step_prompt", "set_gmail_row_state"),
}
for module, names in _RUNTIME_BINDINGS.items():
    for name in names:
        setattr(runtime, name, getattr(module, name))

command = runtime.command
if command == "intake":
    runtime.intake()
elif command == "confirm":
    runtime.confirm()
elif command == "next":
    raise SystemExit(runtime.start_next())
elif command == "report":
    raise SystemExit(runtime.report())
elif command == "gmail":
    raise SystemExit(gmail.gmail_command())
elif command == "obsidian":
    raise SystemExit(obsidian.obsidian_command())
elif command == "notion":
    raise SystemExit(notion.notion_command())
elif command == "imessage":
    raise SystemExit(imessage.imessage_command())
elif command == "apple-notes":
    raise SystemExit(apple_notes.apple_notes_command())
elif command == "apple-reminders":
    raise SystemExit(apple_reminders.apple_reminders_command())
elif command == "install-homebrew":
    raise SystemExit(runtime.install_homebrew_command())
elif command == "agent-memory":
    raise SystemExit(agent_memory.agent_memory_command())
elif command == "fallback":
    raise SystemExit(runtime.fallback_report())
elif command == "actions":
    raise SystemExit(runtime.action_review_command())
elif command == "planner":
    raise SystemExit(runtime.daily_plan_command())
elif command == "status":
    runtime.status()
else:
    print("unknown command: " + command, file=runtime.sys.stderr)
    raise SystemExit(2)
