import SwiftUI

/// Shared chrome for every Task-sidebar picker popover. Mirrors the HTML
/// prototype's `.popover` rule (rounded 8pt corners, hairline border)
/// plus the `.ph` header row.
///
/// The host `panelPopover` uses a borderless NSPanel with `hasShadow=true`
/// and `wantsLayer=true` (set in `PanelPopoverPresenter`), so the system
/// draws the drop shadow following our rounded content's alpha mask. No
/// SwiftUI .shadow / padding is needed — adding either re-introduces the
/// trapezoidal artifact at the cutoff line.
struct TaskPickerContainer<Content: View>: View {
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

/// Standard row used inside every Task-sidebar picker. Renders glyph +
/// label + optional keyboard hint with hover/current background tint.
/// No checkmark — HTML 디자인은 current 상태를 row 배경 색만으로 표시.
struct TaskPickerRow<Glyph: View>: View {
    @ViewBuilder let glyph: () -> Glyph
    let label: String
    let isCurrent: Bool
    let keyLabel: String?
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                glyph().frame(width: 14, height: 14)
                Text(label)
                    .font(.system(size: 13))
                    .foregroundColor(BVColor.fg)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if let keyLabel {
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
