import SwiftUI

/// `↵` / `↑↓` 같이 키보드 키를 시각적으로 표시하는 작은 칩.
///
/// Both `MarkdownChatPill` and `MarkdownChatPillSkillsPicker` used to
/// carry their own copy of this exact 10-line view; centralising it here
/// means a future style tweak (radius, opacity, font size) only edits
/// one spot.
struct MarkdownPillKbdLabel: View {
    let label: String

    init(_ label: String) {
        self.label = label
    }

    var body: some View {
        Text(label)
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundColor(MarkdownPillPalette.textMuted)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}
