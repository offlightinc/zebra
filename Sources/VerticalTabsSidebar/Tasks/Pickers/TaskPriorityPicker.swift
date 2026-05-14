import SwiftUI

struct TaskPriorityPicker: View {
    let current: BrainPriority?
    let onSelect: (BrainPriority?) -> Void

    /// Display order. nil = "No priority" (key 0), then urgent/high/normal/low (1–4).
    private static let ordered: [BrainPriority] = [.urgent, .high, .medium, .low]

    var body: some View {
        TaskPickerContainer(
            title: String(localized: "task.picker.priority.title", defaultValue: "Change priority"),
            width: 200
        ) {
            TaskPickerRow(
                glyph: { TaskNoPriorityGlyph() },
                label: String(localized: "task.priority.none", defaultValue: "No priority"),
                isCurrent: current == nil,
                keyLabel: "0",
                action: { onSelect(nil) }
            )
            .keyboardShortcut(KeyEquivalent("0"), modifiers: [])

            ForEach(Array(Self.ordered.enumerated()), id: \.element) { idx, p in
                TaskPickerRow(
                    glyph: { TaskPriorityIcon(priority: p) },
                    label: p.localizedLabel,
                    isCurrent: current == p,
                    keyLabel: "\(idx + 1)",
                    action: { onSelect(p) }
                )
                .keyboardShortcut(KeyEquivalent(Character("\(idx + 1)")), modifiers: [])
            }
        }
    }
}
