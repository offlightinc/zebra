import SwiftUI

/// 사이드바 Tasks groupBy 픽커. generic `OptionPicker`에 도메인 파라미터만
/// 주입하는 얇은 어댑터.
struct TaskGroupByPicker: View {
    let current: TaskGroupBy
    let onSelect: (TaskGroupBy) -> Void

    var body: some View {
        OptionPicker(
            current: current,
            ordered: TaskGroupBy.allCases,
            title: String(localized: "task.picker.groupBy.title", defaultValue: "Group by"),
            label: { $0.label },
            glyph: { glyph(for: $0) },
            onSelect: { selected in
                if let selected { onSelect(selected) }
            }
        )
    }

    @ViewBuilder
    private func glyph(for groupBy: TaskGroupBy) -> some View {
        switch groupBy {
        case .status:
            StatusGlyph(shape: .openCircle)
        case .priority:
            TaskPriorityIcon(priority: .high)
        case .owner:
            Image(systemName: "person")
                .font(.system(size: 11))
                .foregroundColor(BVColor.fgMute)
        case .project:
            Image(systemName: "folder")
                .font(.system(size: 11))
                .foregroundColor(BVColor.fgMute)
        case .goal:
            Image(systemName: "flag")
                .font(.system(size: 11))
                .foregroundColor(BVColor.fgMute)
        case .none:
            Image(systemName: "slash.circle")
                .font(.system(size: 11))
                .foregroundColor(BVColor.fgFaint)
        }
    }
}
