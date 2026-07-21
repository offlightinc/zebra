---
id: obsidian.direct-markdown
version: v1
sourceID: obsidian
initialStepID: discover_vault
steps:
  - discover_vault
  - confirm_vault_if_needed
  - smoke_read
  - choose_ingest_scope
  - confirm_ingest_plan
  - ingest_markdown
  - verify_readback
  - complete
---

# Obsidian Direct Markdown Source Onboarding

This playbook is derived from the Obsidian ingest playbook draft in brain-offlight and is vendored into Zebra so the helper CLI never depends on the brain repo at runtime.

Use the direct Markdown filesystem path as the primary path. Do not require Obsidian CLI or Clawvisor for Obsidian. The helper CLI is the only Source Onboarding state write path.

## Operating Context

Obsidian vaults are local Markdown knowledge stores. They can contain private notes, credentials, recovery phrases, financial notes, health notes, deployment details, private identifiers, and attachment-heavy folders. Treat smoke read as proof of access only; it is not permission to ingest.

The primary path is direct filesystem discovery/read:

- Prefer a user-provided vault path when present.
- Do not treat Zebra's GBrain write target path as an Obsidian source candidate. That path is the write target context, not the source vault. Do not pass it to `zebra-source-onboarding obsidian verify-vault`.
- A strong vault candidate is a bounded folder with a `.obsidian/` marker and readable `.md` files.
- A direct Markdown folder without `.obsidian/` can be accepted when it has readable `.md` files and is not too broad.
- Obsidian CLI can be used as a helper only if already working, but CLI setup is never required.
- Clawvisor is not part of the Obsidian v1 path.

Automatic discovery reads only the Obsidian app registry at `~/Library/Application Support/obsidian/obsidian.json` and treats each `vaults.*.path` value as a bounded candidate when the path itself contains `.obsidian/`. Do not enumerate iCloud Drive, Documents, CloudStorage, Dropbox, or other home-directory locations as fallback discovery.

If the registry is missing, invalid, unreadable, permission denied, or contains no valid candidates, preserve a compact registry diagnostic and ask the user for the exact Obsidian vault path. Reject broad roots such as Home, Desktop, or Documents. Full Disk Access and blanket folder approval are not recovery steps for this flow.

State rules:

- `source-onboarding-state.json` stores only compact cursor/result fields.
- Use `runStatePath` for compact per-run checkpoint data such as resolved source vault path, scope, acquisition counts, and bounded GBrain receipts.
- Never store prompt bodies, large file lists, or Markdown bodies in Source Onboarding state.
- Markdown content may be written only to the approved ingest artifact after `confirm_ingest_plan`.

Attention rules:

- Use `attention` when the vault path is missing, invalid, too broad, ambiguous, unreadable, or has no Markdown files.
- Use `attention` when a safe ingest sample/scope cannot be selected without user judgment.
- Use `attention` when the target artifact cannot be written or read back.
- User can choose `skip` for Obsidian; skip is explicit and is not the same as failure.

## Step: discover_vault

Work only the Obsidian `discover_vault` step.

Find the Obsidian vault path to use. Do not use Zebra's GBrain write target path as an Obsidian source candidate, even if it contains Markdown files or an `.obsidian/` folder, and do not pass that path to `zebra-source-onboarding obsidian verify-vault`. Prefer bounded `.obsidian/` candidates from the Obsidian app registry. If there is exactly one valid candidate, Zebra may select it and continue to `smoke_read` because ingest is still gated later by scope choice and final plan confirmation. If there are multiple candidates, ask the user which one to use. If there are no valid registry candidates or the registry cannot be used, ask the user for the exact Obsidian vault path. Do not scan other folders automatically.

If you need to explain what path is needed, ask for the folder that contains the user's `.md` notes, usually the folder containing `.obsidian/`. Do not ask the user to install Obsidian CLI.

When you have a candidate path, run:

```bash
zebra-source-onboarding obsidian verify-vault --path "<vault-path>"
```

Continue only from the `nextPrompt` printed by that command.

## Step: confirm_vault_if_needed

Work only the Obsidian `confirm_vault_if_needed` step.

Zebra needs the user to confirm, provide, or correct the Obsidian vault path. Ask for the local folder that contains the notes. A good candidate usually contains a `.obsidian` folder, but for this runner a direct Markdown folder with readable `.md` files can also be accepted when the user explicitly provides it.

If Zebra found no candidate, ask for the correct vault path and run `zebra-source-onboarding obsidian verify-vault --path "<vault-path>"`.

If Zebra found multiple registry candidates, show the list and ask the user which vault to use. Do not choose among them automatically.

If the previous candidate was rejected because it was too broad, explain that Zebra needs the specific vault folder, not the whole home, Desktop, Documents, iCloud Drive, or synced-drive root.

After the user provides a path, run:

```bash
zebra-source-onboarding obsidian verify-vault --path "<vault-path>"
```

Continue only from the `nextPrompt` printed by that command.

## Step: smoke_read

Work only the Obsidian `smoke_read` step.

Run:

```bash
zebra-source-onboarding obsidian smoke-read
```

This is a read-only direct Markdown smoke test. It should prove that at least one Markdown note can be found and opened. It is not ingest approval.

The smoke read should avoid `.obsidian/`, hidden directories, system folders, attachment-like folders, non-Markdown files, and paths outside the selected vault. Empty notes can count as readable, but they are poor ingest samples. If filename matching is tricky because of Unicode normalization, rely on actual paths returned from the Markdown file list instead of typed filename guesses.

Continue only from the `nextPrompt` printed by that command.

## Step: choose_ingest_scope

Work only the Obsidian `choose_ingest_scope` step.

Ask the user which Obsidian content Zebra should ingest now:

- whole vault
- selected folders
- specific note file
- recent/sample subset
- skip Obsidian for now

Tell the user that a large vault can take time and may contain private or sensitive notes. Smoke read success only proves access; it does not authorize ingest. If the user is unsure, recommend a sample/recent subset first.

Scope guidance:

- `whole` is appropriate only when the user explicitly wants the whole vault ingested now.
- `folders` is for named relative folders inside the vault.
- `file` is for one vault-relative Markdown note path. Accept only relative `.md` files inside the selected vault.
- `sample` is for a bounded first ingest, useful for validating the path and artifact/readback behavior.
- `skip` means Obsidian is intentionally skipped for this Source Onboarding session.

When the user chooses, run one of:

```bash
zebra-source-onboarding obsidian choose-scope --scope whole
zebra-source-onboarding obsidian choose-scope --scope folders --folder "<relative-folder>"
zebra-source-onboarding obsidian choose-scope --scope file --file "<relative-note-path.md>"
zebra-source-onboarding obsidian choose-scope --scope sample
zebra-source-onboarding obsidian choose-scope --scope skip
```

For selected folders, pass one `--folder` argument per relative folder. Continue only from the returned `nextPrompt`.

## Step: confirm_ingest_plan

Work only the Obsidian `confirm_ingest_plan` step.

Before ingest, summarize the resolved plan for the user: vault path, selected scope, approximate file count or unknown, excluded paths, expected duration class, ingest mode, and verification plan.

Ask whether to start this ingest plan. If the user approves, run:

```bash
zebra-source-onboarding obsidian confirm-plan --answer yes
```

If the user does not approve, run:

```bash
zebra-source-onboarding obsidian confirm-plan --answer no
```

Do not run ingest before this confirmation is recorded by the helper.

If the user changes scope, return to `choose_ingest_scope`. If the user is worried about sensitive notes, suggest selecting folders or sample scope instead of whole vault.

## Step: ingest_markdown

Work only the Obsidian `ingest_markdown` step.

Run:

```bash
zebra-source-onboarding obsidian ingest
```

This runner writes a bounded source onboarding artifact for the approved Obsidian scope and records compact checkpoint metadata. It must not store Markdown bodies in `source-onboarding-state.json`.

The helper normalizes approved Markdown records in private staging and submits one common GBrain ingestion request. Do not mutate unrelated files or write a connector-owned final artifact.

Continue only from the returned `nextPrompt`.

## Step: verify_readback

Work only the Obsidian `verify_readback` step.

Run:

```bash
zebra-source-onboarding obsidian verify-readback
```

The helper requires exact `gbrain get` readback for every expected slug in the verified source scope. If verification succeeds, Obsidian can be marked complete. If it fails, report the compact attention reason from stdout.

Readback failure means the source is not complete. Keep Obsidian at `attention` or `verify_readback` until the common GBrain receipt succeeds or the user chooses to skip.

## Step: complete

Obsidian Source Onboarding is complete.

Do not run more Obsidian commands unless Zebra prints another Obsidian `nextPrompt`. Briefly tell the user that Obsidian has been ingested for the approved scope.
