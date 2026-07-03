---
id: notion.ntn-cli
version: v1
sourceID: notion
initialStepID: choose_scope
steps:
  - choose_scope
  - smoke_read
  - confirm_workspace_ingest
  - ingest_notion
  - verify_readback
  - complete
---

# Notion ntn CLI Source Onboarding

This playbook drives Zebra Source Onboarding for Notion through the official `ntn` CLI. It is a guided ingest runner, not a blind full-workspace importer. The helper CLI owns state transitions and prints the next executable prompt.

## Step: choose_scope

Ask the user to choose exactly one scope:

1. Page URL/ID 기준으로 현재 page만 가져오기
2. Page URL/ID 기준으로 현재 page와 하위 page까지 가져오기
3. Data source/database URL/ID 기준으로 pages/rows 전체 가져오기
4. URL/ID를 모르면 Notion workspace 후보 찾기
5. Notion workspace 전체 가져오기
6. Notion 건너뛰기

For page scopes, require a page URL or ID. For data source/database scope, require a data source or database URL/ID. Workspace search means authenticated Notion workspace search through `ntn api v1/search page_size:=10`, not web search.

Use one helper command:

```bash
zebra-source-onboarding notion choose-scope --scope page --target "<page-url-or-id>"
zebra-source-onboarding notion choose-scope --scope page-subtree --target "<page-url-or-id>"
zebra-source-onboarding notion choose-scope --scope data-source --target "<data-source-or-database-url-or-id>"
zebra-source-onboarding notion choose-scope --scope workspace-search
zebra-source-onboarding notion choose-scope --scope workspace-all
zebra-source-onboarding notion choose-scope --scope skip
```

Continue only from the `nextPrompt` printed by the command.

## Step: smoke_read

Smoke read is automatic after target scope selection. Do not ask the user for separate smoke-read approval.

- page: `ntn pages get <page-id>`
- data source: `ntn datasources query <data-source-id> --limit 5 --json`
- workspace search: `ntn api v1/search page_size:=10`

If smoke fails, repair the target/auth issue from helper stdout and return to `choose_scope`.

## Step: confirm_workspace_ingest

Whole-workspace ingest requires a second confirmation because it can be broad and expensive.

Warn about expected duration, token/embedding cost possibility, permission gaps, and private/sensitive page inclusion. Do not ingest until the user explicitly confirms with:

```bash
zebra-source-onboarding notion confirm-workspace --answer yes
```

If the user declines, run:

```bash
zebra-source-onboarding notion confirm-workspace --answer no
```

## Step: ingest_notion

Run:

```bash
zebra-source-onboarding notion ingest
```

Convert the selected Notion content into a GBrain markdown artifact with Notion provenance. Do not assume native Notion database ingest. Do not preserve OAuth codes, tokens, signed URLs, credential-like query strings, or broad raw metadata dumps.

Sanitization must cover both URL/query forms and JSON/key-value forms from `ntn` stdout. Examples that must never appear in the artifact include `oauth_code=...`, `code=...`, `"oauth_code":"..."`, `"code":"12345678"`, access/refresh/id tokens, authorization headers, cookies, `secret_*`, `ntn_*`, and signed URL query parameters.

## Step: verify_readback

Run:

```bash
zebra-source-onboarding notion verify-readback
```

The helper verifies Notion provenance and sanitizer output in the generated artifact. If readback finds an unredacted credential-like value, keep the source in `verify_readback` attention instead of completing.

## Step: complete

Notion Source Onboarding is complete. Do not run more Notion commands unless Zebra prints another Notion `nextPrompt`.
