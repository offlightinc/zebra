import SwiftUI

/// 사이드바 Tasks row의 status 인디케이터 클릭 시 뜨는 픽커.
/// generic `OptionPicker`에 도메인 파라미터만 주입하는 얇은 어댑터.
/// HTML 디자인 순서: backlog → todo → inprogress → blocked → done.
/// `waiting`/`canceled`는 legacy 호환용으로만 enum에 존재, picker 노출 안 함.
struct TaskStatusPicker: View {
    let current: BrainTaskStatus?
    let onSelect: (BrainTaskStatus) -> Void

    var body: some View {
        OptionPicker(
            current: current,
            ordered: BrainTaskStatus.primaryCases,
            title: String(localized: "brain.status.picker.title", defaultValue: "Change status"),
            label: { $0.localizedLabel },
            glyph: { StatusGlyph(status: $0) },
            onSelect: { selected in
                if let selected { onSelect(selected) }
            }
        )
    }
}
