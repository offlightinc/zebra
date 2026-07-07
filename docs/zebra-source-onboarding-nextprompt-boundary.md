# Zebra Source Onboarding Completion Boundary

Source Onboarding uses helper command stdout as the primary continuation channel.
The boundary should mirror GBrain section onboarding at the source level: a
source runner can finish its own work, but the next source prompt should not be
returned until the agent reports that completed source back to Zebra.

Every successful command that finishes a selected source must stop at a
completion-pending prompt. The agent must then run:

```bash
zebra-source-onboarding report --status completed --source <source-id>
```

Only the report command may mark that source terminal. It must return a
completed-source handoff with concrete completion details and the instruction to
run `zebra-source-onboarding next`; it must not return the next source prompt.

While a source completion report is pending, all source runner subcommands
(`gmail ...`, `obsidian ...`, `notion ...`, `imessage ...`) must reject with a
completion-report-required response. The response should repeat the pending
source's report prompt. This keeps out-of-order source commands from changing
`activeSourceID` and stranding the completed source in `running/complete`.

The completion-report prompt shape should be:

```text
먼저 사용자에게 이 완료 사실을 짧게 알려주세요:
<completed source summary>

그 다음 아래 명령을 실행하세요:
zebra-source-onboarding report --status completed --source <source-id>
```

The report handoff shape should be:

```text
<Source> Source Onboarding이 완료됐습니다.

- Result: <concrete completed-source result>
- Artifact: <ingested/readback artifact when available>
- Readback: <passed/skipped when available>

이어서 다음 source를 시작하려면 아래 명령을 실행하고, 그 stdout의
`nextPrompt`만 따라 진행하세요:

zebra-source-onboarding next
```

English and Japanese variants should follow the same language resolution used
by Source Onboarding prompts.

This rule exists so the agent does not silently jump from one completed source
into the next source before saying the completed-source result. It keeps Source
Onboarding's stdout `nextPrompt` as the continuation channel while separating
the report side effect from the next-source start side effect.

The boundary applies to source completion only, not every intermediate
smoke-read, scope-selection, ingest, or verification checkpoint. While a source
completion is pending, `zebra-source-onboarding next` must repeat the same
completion-report prompt and must not advance to the next source. Source runner
subcommands must behave the same way: report first, then continue only from the
report handoff by running `zebra-source-onboarding next`.
