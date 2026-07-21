---
id: apple-reminders.eventkit
version: v1
sourceID: apple-reminders
initialStepID: check_reminders_permission
steps:
  - check_reminders_permission
  - smoke_list_reminders
  - choose_ingest_scope
  - confirm_ingest_plan
  - ingest_reminders
  - verify_readback
  - complete
---

# Apple Reminders EventKit Source Onboarding

## Step: check_reminders_permission

Run `zebra-source-onboarding apple-reminders check-access`. This checks whether macOS allows Zebra to read Apple Reminders data; it is not an administrator, installation, or terminal permission.

If the helper returns `reminders_permission_consent_required`, explain that Zebra will only read the scope approved during Source Onboarding and ask one yes/no question. On yes, run `zebra-source-onboarding apple-reminders check-access --permission-answer yes`. On no, run it with `--permission-answer no`.

## Step: smoke_list_reminders

Run `zebra-source-onboarding apple-reminders smoke-list`. This is a read-only metadata check and is not ingest approval. Zero lists or zero open reminders is a successful empty smoke result.

## Step: choose_ingest_scope

Use the helper-generated localized scope prompt. Ask the user to choose all open reminders, one list, today/week, custom, or skip Apple Reminders.

## Step: confirm_ingest_plan

Summarize the selected scope, expected count when known, supported fields, common GBrain ingest/readback plan, and redaction policy. Obtain an explicit yes/no answer before any scoped reminder content read.

## Step: ingest_reminders

Run `zebra-source-onboarding apple-reminders ingest` only after `confirm-plan --answer yes`. Zebra reads only the approved scope through its app-owned EventKit adapter and writes normalized fields, never a raw EventKit dump.

## Step: verify_readback

Run `zebra-source-onboarding apple-reminders verify-readback`. The helper must require the common GBrain receipt and exact source-scoped readback before moving to `complete`.

## Step: complete

Tell the user a short Apple Reminders result summary, then run:

```bash
zebra-source-onboarding report --status completed --source apple-reminders
```

Only after this report succeeds may the agent continue to the next source from the report stdout `nextPrompt`.
