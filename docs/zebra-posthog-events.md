# Zebra PostHog Events

Zebra sends product analytics to the Zebra PostHog project through
`ZebraPostHogAnalytics`. Event names describe the user's action class; event
properties describe the target, mode, value, and privacy-safe object identity.

## Top-Level Events

| Event | Meaning |
| --- | --- |
| `zebra_app_active_daily` | App became active for the first time in a UTC day. |
| `zebra_app_active_hourly` | App became active for the first time in a UTC hour. |
| `zebra_chatpill_prompt_submitted` | User submitted a ChatPill prompt. |
| `zebra_chatpill_toggled` | User expanded or collapsed the ChatPill. |
| `zebra_vault_document_changed` | Vault document lifecycle event; use `action` for `create`, `update`, or `delete`. |
| `zebra_onboarding_start_clicked` | User clicked to start onboarding. |
| `zebra_onboarding_file_created` | Onboarding flow created a file; this is create-only funnel telemetry. |
| `zebra_sidebar_mode_interacted` | User selected or toggled a sidebar mode rail item. |
| `zebra_sidebar_row_selected` | User selected a sidebar row. |
| `zebra_sidebar_picker_changed` | User changed a sidebar picker, such as Goals view mode. |
| `zebra_sidebar_toolbar_changed` | User changed toolbar controls such as filter, sort, or group-by. |
| `zebra_sidebar_item_status_changed` | User changed a task, goal, or email item status from the sidebar. |
| `zebra_sidebar_sync_status_clicked` | User clicked the sync/save status pill. |
| `zebra_sidebar_vault_clicked` | User selected or managed a vault from the sidebar footer. |
| `zebra_sidebar_onboarding_toggled` | User showed or hid the sidebar onboarding/getting-started module. |
| `zebra_inspector_toggled` | User showed or hid the markdown brain-object inspector. |

## Sidebar Properties

All `zebra_sidebar_*` events share a common property vocabulary where
applicable:

| Property | Meaning |
| --- | --- |
| `sidebar_area` | UI area: `mode_rail`, `row`, `picker`, `toolbar`, `status_button`, `vault_button`, or `getting_started`. |
| `sidebar_mode` | Product mode or target: `task`, `goal`, `document`, `email`, `terminal`, `vault`, `sync`, or `onboarding`. |
| `interaction_type` | Normalized action class: `select`, `toggle`, `click`, or `change`. |
| `control_name` | Control that changed, such as `group_by`, `sort`, `filter`, `structure`, `cadence`, `status`, `sync_status`, or `onboarding_visibility`. |
| `selected_value` | Selected state or option, such as `show`, `hide`, `outline`, `cadence`, `synced`, or a status value. |
| `item_id_hash` | SHA-256 hash of a path or item identifier when an event targets a specific item. |

The old broad `zebra_sidebar_interaction` event should not be emitted by new
builds. Use the split `zebra_sidebar_*` events and break down by the common
properties above.

## Document Lifecycle

`zebra_vault_document_changed` is the broad document lifecycle event. Its
`action` property distinguishes `create`, `update`, and `delete`; `object_type`
distinguishes `task`, `goal`, `document`, `page`, or `unknown`.

`zebra_onboarding_file_created` is narrower. It records only file creation from
the onboarding funnel. It can overlap with
`zebra_vault_document_changed action=create change_origin=onboarding`, but the
analysis purpose is different: onboarding conversion versus general document
lifecycle.

## Privacy

Raw prompts, paths, and item identifiers are not sent. Prompt text is bucketed
with `prompt_length_bucket`; paths and item ids are sent as SHA-256 hashes.
