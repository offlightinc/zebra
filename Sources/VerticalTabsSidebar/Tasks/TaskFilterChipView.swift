import SwiftUI

/// A single filter chip. Click body → edit, click ✕ → remove.
struct TaskFilterChipView: View {
    let filter: TaskFilter
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onEdit) {
                HStack(spacing: 4) {
                    Text(filter.field.label)
                        .foregroundColor(BVColor.fgMute)
                    Text(filter.op.symbol)
                        .foregroundColor(BVColor.fgFaint)
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
                    .foregroundColor(BVColor.fgFaint)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
            return BrainTaskStatus(rawValue: raw).map { TaskListViewModel.statusLabel($0) } ?? raw
        case .priority:
            if raw == "__none__" {
                return String(localized: "task.priority.none", defaultValue: "No priority")
            }
            return BrainPriority(rawValue: raw).map { TaskListViewModel.priorityLabel($0) } ?? raw
        case .owner:
            if raw == "__unassigned__" {
                return String(localized: "task.group.unassigned", defaultValue: "Unassigned")
            }
            return raw
        }
    }
}
