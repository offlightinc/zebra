import SwiftUI

/// 사이드바 행 (Tasks / Goals) 의 selection / hover 시각 chrome.
/// - selection: 좌측 2pt accent bar + 행 배경 옅은 accent tint
/// - hover: 회색 tint (selection 보다 약함)
/// - contentShape: 행 전체 hit area
///
/// padding / height 는 row 마다 다르므로 (outline 은 depth × indent, cadence /
/// status 는 flush) 호출자가 본인 책임. modifier 는 background+overlay+
/// contentShape 3가지만 묶음.
struct SidebarRowChrome: ViewModifier {
    let isSelected: Bool
    let isHovered: Bool

    func body(content: Content) -> some View {
        content
            .background(background)
            .overlay(alignment: .leading) {
                if isSelected {
                    Rectangle()
                        .fill(BVColor.accent)
                        .frame(width: 2)
                }
            }
            .contentShape(Rectangle())
    }

    private var background: Color {
        if isSelected { return BVColor.accent.opacity(0.18) }
        if isHovered  { return BVColor.bgHover }
        return Color.clear
    }
}

extension View {
    func sidebarRowChrome(isSelected: Bool, isHovered: Bool) -> some View {
        modifier(SidebarRowChrome(isSelected: isSelected, isHovered: isHovered))
    }
}
