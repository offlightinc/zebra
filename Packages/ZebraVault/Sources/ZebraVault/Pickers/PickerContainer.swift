import SwiftUI

/// Shared chrome for every small-enum popover picker (status, priority,
/// cadence, groupBy 등). HTML 프로토타입 `.popover` 룰을 그대로 따른다 —
/// 8pt 라운드, 1px 보더, 200pt 폭, 옵션 uppercase 타이틀 헤더.
///
/// 호스트 `panelPopover`가 borderless NSPanel + `hasShadow=true`로 시스템
/// shadow를 alpha mask 따라 그리므로, SwiftUI `.shadow`/padding 추가 금지 —
/// 추가하면 cutoff 라인에 사다리꼴 artifact가 다시 생긴다.
struct PickerContainer<Content: View>: View {
    let title: String?
    let width: CGFloat
    @ViewBuilder let content: () -> Content

    init(title: String? = nil, width: CGFloat = 200, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.width = width
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.42)
                    .foregroundColor(BVColor.fgFaint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.top, 6)
                    .padding(.bottom, 4)
            }
            content()
        }
        .padding(.vertical, 4)
        .frame(width: width)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(BVColor.bgElev)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(BVColor.borderStrong, lineWidth: 1)
        )
    }
}

/// 한 옵션을 표시하는 표준 row. glyph + label + 우측 슬롯(✓ 또는 kbd).
/// 단일 선택은 row 배경 틴트로 표시, 다중 선택(필터)은 row 틴트 + 우측 ✓ 둘 다 —
/// HTML 디자인(`.opt.current` + `.check`) 일치.
struct PickerRow<Glyph: View>: View {
    @ViewBuilder let glyph: () -> Glyph
    let label: String
    let isCurrent: Bool
    let keyLabel: String?
    let action: () -> Void
    /// HTML 'Add filter' 행처럼 glyph 슬롯 자체가 없는 경우. true면 glyph 프레임과
    /// HStack spacing을 둘 다 생략해서 라벨이 좌측 패딩에 바로 붙음.
    /// `multiSelectChecked`와는 의미 충돌이 없지만, 같이 true로 두면 라벨이 좌측에
    /// 붙고 우측엔 ✓만 뜨는 비대칭 row가 됨 — 현재 호출자 없음.
    var omitGlyph: Bool = false
    /// 다중 선택 필터의 선택 상태. HTML `.check` ✓ 우측 슬롯. true면 keyLabel과
    /// 의미 충돌이라 ✓가 우선 렌더되고 keyLabel은 무시. HTML도 한 row에 둘 다 두지
    /// 않으므로 호출자는 둘 중 하나만 의도해야 한다.
    var multiSelectChecked: Bool = false

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: omitGlyph ? 0 : 8) {
                if !omitGlyph {
                    glyph().frame(width: 14, height: 14)
                }
                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(BVColor.fg)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if multiSelectChecked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(BVColor.statusCompleted)
                        .frame(minWidth: 12, alignment: .trailing)
                } else if let keyLabel {
                    Text(keyLabel)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(BVColor.fgFaint)
                        .frame(minWidth: 12, alignment: .trailing)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(rowBackground)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .onHover { hovering = $0 }
    }

    private var rowBackground: Color {
        if isCurrent { return BVColor.accent.opacity(0.18) }
        if hovering { return BVColor.bgHover }
        return Color.clear
    }
}

/// Hover-only background helper (현재 선택값 강조 없이 hover만 필요한 자리에 사용).
/// 기존에 `BrainObjectInspectorAtoms.swift`에 있던 helper를 같이 옮김.
struct EditablePickerRowHoverBackground: View {
    @State private var hovering = false
    var body: some View {
        Rectangle()
            .fill(hovering ? BVColor.bgHover : Color.clear)
            .onHover { hovering = $0 }
    }
}
