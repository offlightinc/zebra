import SwiftUI

/// Collapsible section header. Snapshot-only — receives label/count/collapsed
/// state + a toggle closure. No store reference.
struct TaskGroupHeader: View, Equatable {
    let label: String
    let count: Int
    let isCollapsed: Bool
    let onToggle: () -> Void

    static func == (lhs: TaskGroupHeader, rhs: TaskGroupHeader) -> Bool {
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
