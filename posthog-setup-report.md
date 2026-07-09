<wizard-report>
# PostHog post-wizard report

The wizard has completed a PostHog analytics integration for Zebra. The project already had a solid PostHog foundation (`ZebraPostHogAnalytics`, `ZebraTelemetry` sink pattern, and several existing events). This run fixed a critical regression — the bundled API key was a placeholder that prevented any events from firing in release/production builds — and added two new events that extend coverage to key panel interaction flows.

| Event name | Description | File |
|---|---|---|
| `zebra_app_active_daily` | Fires once per UTC day when the app is active | `Sources/Zebra/Environment/ZebraPostHogAnalytics.swift` (existing) |
| `zebra_app_active_hourly` | Fires once per UTC hour when the app is active | `Sources/Zebra/Environment/ZebraPostHogAnalytics.swift` (existing) |
| `zebra_chatpill_prompt_submitted` | User submits an AI prompt via the chat pill | `Sources/Zebra/Environment/ZebraPostHogAnalytics.swift` (existing) |
| `zebra_vault_document_changed` | Vault document created, updated, or deleted | `Sources/Zebra/Environment/ZebraPostHogAnalytics.swift` (existing) |
| `zebra_onboarding_start_clicked` | User clicks to start the onboarding flow | `Sources/Zebra/Environment/ZebraPostHogAnalytics.swift` (existing) |
| `zebra_onboarding_file_created` | File created during onboarding | `Sources/Zebra/Environment/ZebraPostHogAnalytics.swift` (existing) |
| `zebra_sidebar_mode_interacted` | User selects or toggles a sidebar mode rail entry | `Sources/Zebra/Environment/ZebraPostHogAnalytics.swift` (existing) |
| `zebra_sidebar_row_selected` | User selects a task, goal, document, or email row in the sidebar | `Sources/Zebra/Environment/ZebraPostHogAnalytics.swift` (existing) |
| `zebra_sidebar_picker_changed` | User changes a sidebar picker such as the Goals view mode | `Sources/Zebra/Environment/ZebraPostHogAnalytics.swift` (existing) |
| `zebra_sidebar_toolbar_changed` | User changes sidebar toolbar controls such as filter, sort, or group-by | `Sources/Zebra/Environment/ZebraPostHogAnalytics.swift` (existing) |
| `zebra_sidebar_item_status_changed` | User changes a task/goal/email item status from the sidebar | `Sources/Zebra/Environment/ZebraPostHogAnalytics.swift` (existing) |
| `zebra_sidebar_sync_status_clicked` | User clicks the sync/save status pill in the sidebar footer | `Sources/Zebra/Environment/ZebraPostHogAnalytics.swift` (existing) |
| `zebra_sidebar_vault_clicked` | User selects or manages a vault from the sidebar footer | `Sources/Zebra/Environment/ZebraPostHogAnalytics.swift` (existing) |
| `zebra_sidebar_onboarding_toggled` | User shows or hides the sidebar getting-started/onboarding module | `Sources/Zebra/Environment/ZebraPostHogAnalytics.swift` (existing) |
| `zebra_chatpill_toggled` | User expands or collapses the ChatPill overlay in a markdown panel | `Sources/Zebra/Panels/ZebraMarkdownPanelView.swift` (**new**) |
| `zebra_inspector_toggled` | User shows or hides the brain-object inspector for a markdown document | `Sources/Zebra/Panels/MarkdownPanelController.swift` (**new**) |

### Key changes made

- **`Sources/Zebra/Environment/ZebraPostHogAnalytics.swift`** — replaced placeholder `bundledAPIKey` with the real PostHog public token so release builds send events; added `trackChatPillToggled` and `trackInspectorToggled` capture methods plus `ZebraTelemetryPostHogBridge` sink implementations. Sidebar telemetry is split into area-level top-level events instead of the former broad `zebra_sidebar_interaction` event, with shared properties `sidebar_area`, `sidebar_mode`, `interaction_type`, `control_name`, `selected_value`, and `item_id_hash`.
- **`Packages/ZebraVault/Sources/ZebraVault/Telemetry/ZebraTelemetry.swift`** — added `ZebraTelemetryChatPillToggledEvent` and `ZebraTelemetryInspectorToggledEvent` structs; extended `ZebraTelemetrySink` protocol and `ZebraTelemetry` dispatch enum with `trackChatPillToggled` and `trackInspectorToggled`.
- **`Sources/Zebra/Panels/ZebraMarkdownPanelView.swift`** — added `.onChange(of: chatPillExpanded)` to fire `zebra_chatpill_toggled`.
- **`Sources/Zebra/Panels/MarkdownPanelController.swift`** — added `ZebraTelemetry.trackInspectorToggled` call inside `toggleInspector()`.
- **`.env`** — added `ZEBRA_POSTHOG_API_KEY` for Xcode scheme-based debug overrides.

## Next steps

We've built some insights and a dashboard for you to keep an eye on user behavior, based on the events we just instrumented:

- [Analytics basics (wizard) dashboard](https://us.posthog.com/project/504247/dashboard/1821033)
- [Daily active users](https://us.posthog.com/project/504247/insights/6jHoGYuL)
- [AI prompt submissions by surface](https://us.posthog.com/project/504247/insights/BE9wBbNw)
- [Vault document changes by action](https://us.posthog.com/project/504247/insights/eV0BGE91)
- [Onboarding conversion funnel](https://us.posthog.com/project/504247/insights/7aMbMMRp)
- [Sidebar interactions by surface](https://us.posthog.com/project/504247/insights/jt1YCUBm)

Note: sidebar insights created before the taxonomy split may need to be rebuilt from the new `zebra_sidebar_*` events.

## Verify before merging

- [ ] Run a full production build (the wizard only verified the files it touched) and fix any lint or type errors introduced by the generated code.
- [ ] Run the test suite — call sites that were rewritten or instrumented may need updated mocks or fixtures.
- [ ] Add `ZEBRA_POSTHOG_API_KEY` to `.env.example` (or any bootstrap script) so collaborators know to set it for Xcode scheme-based debug testing.

### Agent skill

We've left an agent skill folder in your project. You can use this context for further agent development when using Claude Code. This will help ensure the model provides the most up-to-date approaches for integrating PostHog.

</wizard-report>
