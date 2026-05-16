import SwiftUI

/// A single filter chip. Click body → edit, click ✕ → remove.
struct TaskFilterChipView: View {
    let filter: TaskFilter
    let onEdit: () -> Void
    let onRemove: () -> Void

    @State private var closeHover = false

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onEdit) {
                HStack(spacing: 4) {
                    Text(filter.field.label)
                        .foregroundColor(BVColor.fgMute)
                    Text(filter.op.symbol)
                        .foregroundColor(BVColor.fgFaint)
                        .padding(.horizontal, 2)
                    Text(valueLabel)
                        .foregroundColor(BVColor.fg)
                }
                .font(.system(size: 11))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(closeHover ? BVColor.fg : BVColor.fgFaint)
                    .frame(width: 14, height: 14)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(closeHover ? BVColor.bgHover : Color.clear)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { closeHover = $0 }
        }
        .padding(.leading, 7).padding(.trailing, 2)
        .frame(height: 20)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(BVColor.bgInput)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(BVColor.border))
        )
    }

    private var valueLabel: String {
        if filter.values.isEmpty {
            return String(localized: "task.filter.empty", defaultValue: "(none)")
        }
        let displayed = filter.values.prefix(2).map { rawValueLabel($0) }.joined(separator: ", ")
        let extra = filter.values.count > 2 ? " +\(filter.values.count - 2)" : ""
        return displayed + extra
    }

    private func rawValueLabel(_ raw: String) -> String {
        switch filter.field {
        case .status:
            if raw == "__unrecognized__" {
                return String(localized: "task.group.unrecognized", defaultValue: "Unrecognized")
            }
            return BrainTaskStatus(rawValue: raw).map { $0.localizedLabel } ?? raw
        case .priority:
            if raw == "__none__" {
                return String(localized: "task.priority.none", defaultValue: "No priority")
            }
            // legacy "normal" → .medium 흡수
            if raw == "normal" { return BrainPriority.medium.localizedLabel }
            return BrainPriority(rawValue: raw).map { $0.localizedLabel } ?? raw
        case .owner:
            if raw == "__unassigned__" {
                return String(localized: "task.group.unassigned", defaultValue: "Unassigned")
            }
            return raw
        }
    }
}

/// HTML `.chiprow { flex-wrap: wrap; gap: 5px; }` 와 동치인 줄바꿈 HStack.
/// 컨테이너 너비를 넘는 자식은 다음 줄로 흐른다. Layout 프로토콜 기반(macOS 13+).
struct TaskChipFlowLayout: Layout {
    var spacing: CGFloat = 5

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width
            maxX = max(maxX, x)
            rowHeight = max(rowHeight, size.height)
            x += spacing
        }
        let totalWidth = maxWidth.isFinite ? maxWidth : maxX
        return CGSize(width: totalWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        let maxX = bounds.maxX
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
