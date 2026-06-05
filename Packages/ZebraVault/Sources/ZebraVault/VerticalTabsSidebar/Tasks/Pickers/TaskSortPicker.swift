import SwiftUI

/// 사이드바 Tasks sort 픽커. `TaskGroupByPicker`와 같은 chrome을 쓰는
/// 도메인 어댑터.
struct TaskSortPicker: View {
    let current: TaskSort
    let direction: TaskSortDirection
    let onSelect: (TaskSort) -> Void

    var body: some View {
        PickerContainer(
            title: String(localized: "task.picker.sort.title", defaultValue: "Sort by")
        ) {
            ForEach(TaskSort.allCases, id: \.self) { sort in
                PickerRow(
                    glyph: { glyph(for: sort) },
                    label: sort.label,
                    isCurrent: current == sort,
                    keyLabel: direction(for: sort).symbol,
                    action: { onSelect(sort) }
                )
            }
        }
    }

    private func direction(for sort: TaskSort) -> TaskSortDirection {
        current == sort ? direction : sort.defaultDirection
    }

    @ViewBuilder
    private func glyph(for sort: TaskSort) -> some View {
        switch sort {
        case .title:
            Image(systemName: "textformat")
                .font(.system(size: 11))
                .foregroundColor(BVColor.fgMute)
        case .due:
            Image(systemName: "calendar")
                .font(.system(size: 11))
                .foregroundColor(BVColor.fgMute)
        case .created:
            Image(systemName: "plus.circle")
                .font(.system(size: 11))
                .foregroundColor(BVColor.fgMute)
        case .updated:
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 11))
                .foregroundColor(BVColor.fgMute)
        }
    }
}
