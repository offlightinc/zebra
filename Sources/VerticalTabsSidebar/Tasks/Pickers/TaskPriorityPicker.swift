import SwiftUI

/// 사이드바 Tasks priority 픽커. generic `OptionPicker`에 도메인 파라미터만
/// 주입하는 얇은 어댑터. 키 0 → "No priority"(nil), 1–4 → urgent/high/normal/low.
struct TaskPriorityPicker: View {
    let current: BrainPriority?
    let onSelect: (BrainPriority?) -> Void

    private static let ordered: [BrainPriority] = [.urgent, .high, .medium, .low]

    var body: some View {
        OptionPicker(
            current: current,
            ordered: Self.ordered,
            title: String(localized: "task.picker.priority.title", defaultValue: "Change priority"),
            label: { $0.localizedLabel },
            glyph: { TaskPriorityIcon(priority: $0) },
            noneRow: .init(
                label: String(localized: "task.priority.none", defaultValue: "No priority"),
                glyph: AnyView(TaskNoPriorityGlyph())
            ),
            onSelect: onSelect
        )
    }
}
