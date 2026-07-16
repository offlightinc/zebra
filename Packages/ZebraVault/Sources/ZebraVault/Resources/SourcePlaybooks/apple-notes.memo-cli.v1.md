---
id: apple-notes.memo-cli
version: v1
sourceID: apple-notes
initialStepID: check_memo_cli
steps:
  - check_memo_cli
  - check_notes_automation
  - smoke_list_notes
  - choose_ingest_scope
  - confirm_ingest_plan
  - ingest_notes
  - verify_readback
  - complete
---

# Apple Notes memo CLI Source Onboarding

## Step: check_memo_cli

Work only the Apple Notes `check_memo_cli` step.

Run:

```bash
zebra-source-onboarding apple-notes check-cli
```

The helper checks both `memo` and Homebrew before asking anything. Follow its returned single install-plan question exactly: if Homebrew exists it asks to install only `memo`; if both are missing it asks once to install Homebrew and `memo` together. Run the exact `--install-answer` command from helper stdout after the user answers. Never create a second install-consent question, and do not install anything unless the user explicitly answers yes.

If the approved plan needs Homebrew, follow the helper's exact Hermes PTY-backed terminal tool instructions. Do not open a separate Zebra terminal.

Continue only from the returned `nextPrompt`.

## Step: check_notes_automation

Run `zebra-source-onboarding apple-notes check-access`. If macOS denies Notes.app Automation access, ask the user to grant Automation permission to the runtime that is running this onboarding step.

## Step: smoke_list_notes

Run `zebra-source-onboarding apple-notes smoke-list`. This verifies read-only folder/list access only. It is not ingest approval.

## Step: choose_ingest_scope

Ask the user to choose one Apple Notes ingest scope: folder, search query, selected note IDs, small sample, or skip Apple Notes for now. Do not start a broad all-notes ingest by default.

## Step: confirm_ingest_plan

Summarize the selected Apple Notes ingest plan and run `zebra-source-onboarding apple-notes confirm-plan --answer yes` only after explicit approval.

## Step: ingest_notes

Run `zebra-source-onboarding apple-notes ingest`.

## Step: verify_readback

Run `zebra-source-onboarding apple-notes verify-readback`.

## Step: complete

Apple Notes Source Onboarding is complete.
