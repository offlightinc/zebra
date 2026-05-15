import SwiftUI

/// 사이드바 (Tasks / Goals) 의 collapsible section 헤더. 도메인-중립.
/// `onToggle: {}` + `isCollapsed: false` 로 호출하면 비-collapsible (구조 모드
/// 의 "Goals · N" 같은 정적 헤더) 로도 사용 가능.
///
/// Snapshot-only — receives label/count/collapsed state + a toggle closure.
/// No store reference.
struct SidebarSectionHeader: View, Equatable {
    let label: String
    let count: Int
    let isCollapsed: Bool
    let onToggle: () -> Void

    static func == (lhs: SidebarSectionHeader, rhs: SidebarSectionHeader) -> Bool {
        lhs.label == rhs.label && lhs.count == rhs.count && lhs.isCollapsed == rhs.isCollapsed
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                Text(label.uppercased())
                    .font(.system(size: 10.5, weight: .bold))
                    .tracking(0.8)
                    .foregroundColor(BVColor.fgMute)
                Text("\(count)")
                    .font(.system(size: 11))
                    .foregroundColor(BVColor.fgFaint)
                Spacer()
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(BVColor.fgFaint)
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
