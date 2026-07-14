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

If `memo` is missing, report the helper's compact attention reason and tell the user Apple Notes ingest requires the `memo` CLI. Show this Homebrew install command:

```bash
brew tap antoniorodr/memo && brew install antoniorodr/memo/memo
```

Then ask an explicit yes/no question before installing:

```text
Apple Notes ingest requires the memo CLI. Install it now with Homebrew? (yes/no)
```

Do not install anything unless the user explicitly answers yes.

If Homebrew itself is missing, obtain separate Homebrew install consent and run `zebra-source-onboarding apple-notes check-cli --homebrew-install-answer yes`. Follow the helper's exact Hermes PTY-backed terminal tool instructions. Use `no` if the user declines. Do not open a separate Zebra terminal.

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
