import SwiftUI

/// 사이드바 Tasks groupBy 픽커. generic `OptionPicker`에 도메인 파라미터만
/// 주입하는 얇은 어댑터. glyph 없음(EmptyView).
struct TaskGroupByPicker: View {
    let current: TaskGroupBy
    let onSelect: (TaskGroupBy) -> Void

    var body: some View {
        OptionPicker(
            current: current,
            ordered: TaskGroupBy.allCases,
            title: String(localized: "task.picker.groupBy.title", defaultValue: "Group by"),
            label: { $0.label },
            glyph: { _ in EmptyView() },
            onSelect: { selected in
                if let selected { onSelect(selected) }
            }
        )
    }
}
