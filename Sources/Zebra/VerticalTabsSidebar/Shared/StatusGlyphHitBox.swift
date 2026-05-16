import SwiftUI

/// 사이드바 status 글리프 버튼의 hit-box 시각 chrome. 14×14 frame +
/// hover scale + 박스 전체 hit area. hover 상태는 호출자가 `@State` 로 갖고
/// 전달 — modifier 자체엔 state 없음.
struct StatusGlyphHitBox: ViewModifier {
    let hover: Bool

    func body(content: Content) -> some View {
        content
            .frame(width: 14, height: 14)
            .scaleEffect(hover ? 1.08 : 1.0)
            .contentShape(Rectangle())
    }
}

extension View {
    func statusGlyphHitBox(hover: Bool) -> some View {
        modifier(StatusGlyphHitBox(hover: hover))
    }
}
