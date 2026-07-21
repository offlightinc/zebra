import common as runtime
from connectors import obsidian, agent_memory, notion, imessage, apple_notes, apple_reminders, gmail

_MODULES = (obsidian, agent_memory, notion, imessage, apple_notes, apple_reminders, gmail)
_NAMESPACES = (runtime, *_MODULES)
for module in _MODULES:
    for name, value in vars(module).items():
        if name.startswith("_"):
            continue
        for namespace in _NAMESPACES:
            setattr(namespace, name, value)

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
    raise SystemExit(runtime.gmail_command())
elif command == "obsidian":
    raise SystemExit(runtime.obsidian_command())
elif command == "notion":
    raise SystemExit(runtime.notion_command())
elif command == "imessage":
    raise SystemExit(runtime.imessage_command())
elif command == "apple-notes":
    raise SystemExit(runtime.apple_notes_command())
elif command == "apple-reminders":
    raise SystemExit(runtime.apple_reminders_command())
elif command == "install-homebrew":
    raise SystemExit(runtime.install_homebrew_command())
elif command == "agent-memory":
    raise SystemExit(runtime.agent_memory_command())
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
