import SwiftUI

/// 사이드바 (Tasks / Goals) 의 section 헤더. 도메인-중립.
/// `onToggle: nil` 이면 정적 라벨 (chevron 안 그리고 Button 도 안 감쌈) —
/// 구조 모드의 "Goals · N" 이나 UNKNOWN bucket 처럼 접기 불가능한 자리에 사용.
/// `onToggle` 이 있으면 collapsible: chevron 표시 + 전체 행 클릭으로 토글.
///
/// Snapshot-only — receives label/count/collapsed state + an optional toggle
/// closure. No store reference.
struct SidebarSectionHeader: View, Equatable {
    let label: String
    let count: Int
    let isCollapsed: Bool
    let onToggle: (() -> Void)?

    static func == (lhs: SidebarSectionHeader, rhs: SidebarSectionHeader) -> Bool {
        lhs.label == rhs.label
            && lhs.count == rhs.count
            && lhs.isCollapsed == rhs.isCollapsed
            && (lhs.onToggle == nil) == (rhs.onToggle == nil)
    }

    var body: some View {
        if let onToggle {
            Button(action: onToggle) {
                content(showsChevron: true)
            }
            .buttonStyle(.plain)
        } else {
            content(showsChevron: false)
        }
    }

    @ViewBuilder
    private func content(showsChevron: Bool) -> some View {
        HStack(spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 10.5, weight: .bold))
                .tracking(0.8)
                .foregroundColor(BVColor.fgMute)
            Text("\(count)")
                .font(.system(size: 11))
                .foregroundColor(BVColor.fgFaint)
            Spacer()
            if showsChevron {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(BVColor.fgFaint)
            }
        }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 4)
        .contentShape(Rectangle())
    }
}
