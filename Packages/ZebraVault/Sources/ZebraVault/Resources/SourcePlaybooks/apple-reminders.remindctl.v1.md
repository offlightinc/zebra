---
id: apple-reminders.remindctl
version: v1
sourceID: apple-reminders
initialStepID: check_remindctl_cli
steps:
  - check_remindctl_cli
  - check_reminders_permission
  - smoke_list_reminders
  - choose_ingest_scope
  - confirm_ingest_plan
  - ingest_reminders
  - verify_readback
  - complete
---

# Apple Reminders remindctl Source Onboarding

## Step: check_remindctl_cli

Run `zebra-source-onboarding apple-reminders check-cli`.

If `remindctl` is missing, use the helper's install-consent flow. Homebrew install consent and remindctl install consent are separate user choices. Do not install Homebrew or remindctl unless the user explicitly answers yes for that specific install.

Primary remindctl install command:

```bash
brew install steipete/tap/remindctl
```

Source build is an advanced fallback only; do not present it as the normal onboarding path.

## Step: check_reminders_permission

Run `zebra-source-onboarding apple-reminders check-access`.

The macOS Reminders permission prompt can attach to the runtime process that executes remindctl, such as Terminal, OpenClaw node/agent, or the Zebra runtime. If access remains denied or not determined, guide the user to System Settings > Privacy & Security > Reminders and allow the actual runtime process.

## Step: smoke_list_reminders

Run `zebra-source-onboarding apple-reminders smoke-list`.

Smoke is read-only verification and is not ingest approval. Empty arrays can mean access succeeded and the selected scope has no reminders.

## Step: choose_ingest_scope

Use the helper-generated localized scope prompt for the active onboarding language. Do not paste an English-only list when `ZEBRA_ONBOARDING_LANGUAGE` is `ko` or `ja`.

Ask the user to choose one of these presets, translated for the active language:

1. All open reminders
2. One list
3. Today or this week
4. Custom
5. Skip Apple Reminders for now

Use custom for completed reminders, overdue-only, multiple lists, all including completed, or item cap/sample choices. Do not make a sample cap the default ingest limit.

## Step: confirm_ingest_plan

Summarize selected list/date/status/completed scope, full versus bounded scope, expected count, returned fields, unsupported fields, artifact path, readback plan, and redaction policy. Ask for explicit yes/no approval before ingest.

## Step: ingest_reminders

Run `zebra-source-onboarding apple-reminders ingest` only after `confirm-plan --answer yes`.

Write only the approved scope. Do not store a raw JSON dump. Store only fields that remindctl actually returned. Do not invent sections, smart lists, tags, attachments, urgent/private flags, or other unsupported fields.

## Step: verify_readback

Run `zebra-source-onboarding apple-reminders verify-readback`.

If readback succeeds, the helper must move to `complete` and return a completion-report prompt. Do not start the next source from `verify-readback` directly.

## Step: complete

Tell the user a short Apple Reminders result summary, then run:

```bash
zebra-source-onboarding report --status completed --source apple-reminders
```

Only after this report command succeeds may the agent continue to the next source from the report stdout `nextPrompt`.
