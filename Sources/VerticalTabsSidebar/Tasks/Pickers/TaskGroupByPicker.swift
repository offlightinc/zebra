import SwiftUI

struct TaskGroupByPicker: View {
    let current: TaskGroupBy
    let onSelect: (TaskGroupBy) -> Void

    var body: some View {
        TaskPickerContainer(
            title: String(localized: "task.picker.groupBy.title", defaultValue: "Group by"),
            width: 200
        ) {
            ForEach(Array(TaskGroupBy.allCases.enumerated()), id: \.element) { idx, opt in
                TaskPickerRow(
                    glyph: { EmptyView() },
                    label: opt.label,
                    isCurrent: current == opt,
                    keyLabel: nil,
                    action: { onSelect(opt) }
                )
                .keyboardShortcut(KeyEquivalent(Character("\(idx + 1)")), modifiers: [])
            }
        }
    }
}
