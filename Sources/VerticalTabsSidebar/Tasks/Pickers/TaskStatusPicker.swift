import SwiftUI

struct TaskStatusPicker: View {
    let current: BrainTaskStatus?
    let onSelect: (BrainTaskStatus) -> Void

    // HTML 디자인 picker 순서: backlog → todo → inprogress(doing) → blocked → done(completed).
    private static let ordered: [BrainTaskStatus] = BrainTaskStatus.primaryCases

    var body: some View {
        TaskPickerContainer(
            title: String(localized: "task.picker.status.title", defaultValue: "Change status"),
            width: 200
        ) {
            ForEach(Array(Self.ordered.enumerated()), id: \.element) { idx, status in
                TaskPickerRow(
                    glyph: { StatusGlyph(status: status) },
                    label: status.localizedLabel,
                    isCurrent: current == status,
                    keyLabel: "\(idx + 1)",
                    action: { onSelect(status) }
                )
                .keyboardShortcut(KeyEquivalent(Character("\(idx + 1)")), modifiers: [])
            }
        }
    }
}
