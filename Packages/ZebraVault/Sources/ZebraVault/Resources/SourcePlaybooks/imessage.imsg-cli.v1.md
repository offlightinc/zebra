---
id: imessage.imsg-cli
version: v1
sourceID: imessage
initialStepID: check_imsg_cli
steps:
  - check_imsg_cli
  - check_full_disk_access
  - smoke_history
  - choose_ingest_scope
  - confirm_ingest_plan
  - ingest_messages
  - verify_readback
  - complete
---

# iMessage CLI Source Onboarding

This playbook is derived from the iMessage ingest playbook draft in brain-offlight and is vendored into Zebra so the helper CLI never depends on the brain repo at runtime.

iMessage is a high-sensitivity local macOS communication source. Smoke read is a read-only capability check, not ingest approval. Actual ingest must happen only after the user chooses a conversation scope and confirms the ingest plan.

## Operating Context

The primary path is the local `imsg` CLI against the macOS Messages database. It may require Full Disk Access for the process chain that actually runs the command. Missing `imsg`, missing Messages access, or a failing history read should be recorded as compact attention reasons instead of being collapsed into "no messages."

State rules:

- `source-onboarding-state.json` stores only compact cursor/result fields.
- Use `runStatePath` for compact per-run checkpoint data such as CLI path, access status, smoke outcome, selected scope, internal bounded window, thread-level limit, and bounded GBrain receipts.
- Never store raw message bodies, large chat/history JSON, prompt bodies, or transcripts in Source Onboarding state.

Attention rules:

- Use `attention` when `imsg` is missing, Messages database access is denied, history smoke read fails, ingest scope is missing, ingest plan is unconfirmed, or readback fails.
- Report Messages DB listing/access preflight failure as `messages_full_disk_access_missing`, but report `imsg history` failures as `history_read_failed`.
- If the approved scope resolves to zero conversations, keep iMessage in `attention` with `no_threads_in_approved_scope` instead of writing an empty completed ingest.
- Use `skipped` only when the user explicitly skips iMessage for this Source Onboarding session.
- User can retry setup/scope or skip; attention is not complete.

## Step: check_imsg_cli

Work only the iMessage `check_imsg_cli` step.

Run:

```bash
zebra-source-onboarding imessage check-cli
```

If `imsg` is missing, report the helper's compact attention reason and tell the user the expected install path is the `imsg` CLI, commonly installed with Homebrew from `steipete/tap/imsg`. Do not install anything unless the user explicitly asks.

Continue only from the returned `nextPrompt`.

## Step: check_full_disk_access

Work only the iMessage `check_full_disk_access` step.

Run:

```bash
zebra-source-onboarding imessage check-access
```

If access is denied, explain that macOS Full Disk Access may need to be granted to the runtime process that is running Source Onboarding. Do not treat this as "no messages" or source completion.

Continue only from the returned `nextPrompt`.

## Step: smoke_history

Work only the iMessage `smoke_history` step.

Run:

```bash
zebra-source-onboarding imessage smoke-history
```

This is a minimal read-only history access check. It is not ingest approval. If the smoke read passes, continue to scope selection.

Continue only from the returned `nextPrompt`.

## Step: choose_ingest_scope

Work only the iMessage `choose_ingest_scope` step.

Ask the user:

```text
iMessage 접근 확인은 끝났습니다. 이제 실제로 brain에 저장할 대화방 범위를 정해야 합니다.

어떤 범위로 가져올까요?

1. 최근 날짜 이후 업데이트된 대화방
2. 특정 대화방
3. 대화방 전체
4. 지금은 iMessage 건너뛰기
```

When the user chooses, run one of:

```bash
zebra-source-onboarding imessage choose-scope --scope updated-since --since YYYY-MM-DD
zebra-source-onboarding imessage choose-scope --scope selected-threads --chat-id "<chat-id>"
zebra-source-onboarding imessage choose-scope --scope all-threads
zebra-source-onboarding imessage choose-scope --scope skip
```

Do not expose message-count slicing as a user option. The helper can keep an internal bounded window/checkpoint and report it in the confirm plan. If `updated-since` or `all-threads` resolves conversations through a bounded chat listing, the thread-level limit must be shown in the confirm plan.

For selected conversations, use the helper-provided candidate list. Prefer `contact_name`, `display_name`, or `name` when available; otherwise show a formatted phone/email handle. Do not present raw `chat_id=... service=... name=... last=...` dumps to the user.

Continue only from the returned `nextPrompt`.

## Step: confirm_ingest_plan

Work only the iMessage `confirm_ingest_plan` step.

Before ingest, summarize the selected conversation scope, any since date or selected thread IDs, internal bounded window/checkpoint, expected sensitivity, ingest mode, and verification plan.

Tell the user that the approved scope may store raw message text, phone/email identifiers, contact names, OTP/security texts, timestamps, thread/message IDs, and attachment/reaction metadata.

If the user approves, run:

```bash
zebra-source-onboarding imessage confirm-plan --answer yes
```

If the user does not approve, run:

```bash
zebra-source-onboarding imessage confirm-plan --answer no
```

Do not run ingest before this confirmation is recorded by the helper.

## Step: ingest_messages

Work only the iMessage `ingest_messages` step.

Run:

```bash
zebra-source-onboarding imessage ingest
```

This helper slice writes a bounded source onboarding artifact for the approved iMessage scope and records compact checkpoint metadata. It must not store raw message bodies in `source-onboarding-state.json`.

Continue only from the returned `nextPrompt`.

## Step: verify_readback

Work only the iMessage `verify_readback` step.

Run:

```bash
zebra-source-onboarding imessage verify-readback
```

The helper requires exact `gbrain get` readback for every expected conversation record in the verified source scope. If verification succeeds, iMessage can be marked complete. If it fails, report the compact attention reason from stdout.

## Step: complete

iMessage Source Onboarding is complete.

Do not run more iMessage commands unless Zebra prints another iMessage `nextPrompt`. Briefly tell the user that iMessage has been ingested for the approved scope.
