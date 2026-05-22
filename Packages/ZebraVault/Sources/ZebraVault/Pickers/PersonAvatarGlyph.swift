import SwiftUI

/// slug 첫 글자 + `BrainPersonColor.color(for:)` 원형 뱃지. picker row glyph
/// (14pt), owner chip, toolbar 헤더 (16pt) 등 size 가 다른 호출처를 한 패턴으로
/// 묶기 위한 헬퍼. 폰트 크기는 size * 0.64 비율 — 기존 14pt/9pt 짝과 같은 비율.
struct PersonAvatarGlyph: View {
    let slug: String
    let size: CGFloat

    var body: some View {
        Text(String(slug.prefix(1)).uppercased())
            .font(.system(size: size * 0.64, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(BrainPersonColor.color(for: slug)))
    }
}
