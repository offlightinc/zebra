import SwiftUI

/// 도메인 무관 generic 옵션 픽커. 작은 정적 enum(≤9 옵션, none 포함 시 ≤10)을
/// 같은 chrome / 같은 row 스타일 / 같은 키보드 룰(1–N, none은 0)으로 렌더링.
///
/// `BrainOptionPicker`(체크마크식)·기존 `CadencePickerView`(자체 챕터)·사이드바
/// `TaskStatusPicker`/`TaskPriorityPicker`/`TaskGroupByPicker`까지 모두 이걸로
/// 통합. 도메인별 차이(ordering, label, glyph, none 슬롯)는 call site 주입.
///
/// 검색·스크롤·multi-select 픽커(`OwnerPickerView`, `TaskFilterValuePicker` 등)는
/// 패러다임이 다르므로 이 픽커를 쓰지 않는다.
struct OptionPicker<Option: Hashable, Glyph: View>: View {
    let current: Option?
    let ordered: [Option]
    let title: String
    var width: CGFloat = 200
    let label: (Option) -> String
    @ViewBuilder let glyph: (Option) -> Glyph
    var noneRow: NoneRow? = nil
    /// nil은 noneRow가 있을 때만 전달된다.
    let onSelect: (Option?) -> Void

    /// "no value" 행 슬롯. glyph는 도메인별로 View 타입이 달라 `AnyView`로 받음.
    /// 호출자 1곳(priority)뿐이라 두 번째 generic 파라미터로 노출할 가치 없음.
    struct NoneRow {
        let label: String
        let glyph: AnyView
    }

    var body: some View {
        // ForEach가 idx+1로 키 문자를 만드는데 `Character("\(n)")`는 multi-digit
        // 문자열에서 trap. 옵션 키는 1–9까지만 허용. (none은 별도로 키 0을 차지.)
        let _ = precondition(ordered.count <= 9, "OptionPicker supports up to 9 ordered options (keys 1–9). Got \(ordered.count).")

        PickerContainer(title: title, width: width) {
            if let none = noneRow {
                PickerRow(
                    glyph: { none.glyph },
                    label: none.label,
                    isCurrent: current == nil,
                    keyLabel: "0",
                    action: { onSelect(nil) }
                )
                .keyboardShortcut(KeyEquivalent("0"), modifiers: [])
            }
            ForEach(Array(ordered.enumerated()), id: \.element) { idx, option in
                let keyChar = Character("\(idx + 1)")
                PickerRow(
                    glyph: { glyph(option) },
                    label: label(option),
                    isCurrent: current == option,
                    keyLabel: "\(idx + 1)",
                    action: { onSelect(option) }
                )
                .keyboardShortcut(KeyEquivalent(keyChar), modifiers: [])
            }
        }
    }
}
