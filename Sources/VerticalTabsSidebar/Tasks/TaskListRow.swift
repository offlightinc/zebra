import SwiftUI

/// Snapshot-only row: receives a value `TaskItem` and a closure bundle.
/// Per CLAUDE.md "Snapshot boundary for list subtrees" — must NOT hold
/// any ObservableObject reference.
struct TaskListRow: View, Equatable {
    let task: TaskItem
    let isSelected: Bool
    let onOpen: (TaskItem) -> Void
    let onChangeStatus: (TaskItem, BrainTaskStatus) -> Void
    let onChangePriority: (TaskItem, BrainPriority?) -> Void
    let onChangeDue: (TaskItem, Date?) -> Void

    @State private var showStatusPicker = false
    @State private var showPriorityPicker = false
    @State private var showDuePicker = false
    @State private var statusHover = false
    @State private var priorityHover = false
    @State private var rowHover = false

    static func == (lhs: TaskListRow, rhs: TaskListRow) -> Bool {
        lhs.task == rhs.task && lhs.isSelected == rhs.isSelected
    }

    var body: some View {
        HStack(spacing: 8) {
            statusButton
            Text(task.title)
                .font(.system(size: 13))
                .foregroundColor(isCompleted ? BVColor.fgMute : BVColor.fg)
                .strikethrough(isCompleted, color: BVColor.fgMute.opacity(0.5))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !isCompleted, let due = task.dueDate {
                Button(action: { showDuePicker = true }) {
                    Text(dueLabel(due))
                        .font(.system(size: 11, weight: dueWeight(due)).monospacedDigit())
                        .foregroundColor(dueColor(due))
                }
                .buttonStyle(.plain)
                .panelPopover(isPresented: $showDuePicker) {
                    TaskDuePopover(current: due) { newDate in
                        onChangeDue(task, newDate)
                        showDuePicker = false
                    }
                }
            } else if task.dueDate != nil {
                // Done: empty slot, keep priority anchor stable
                Spacer().frame(width: 0)
            }
            priorityButton
            if let raw = task.unrecognizedStatusRaw {
                Text("?\(raw)")
                    .font(.system(size: 9.5).monospaced())
                    .foregroundColor(.white)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color.red.opacity(0.7)))
                    .help(String(localized: "task.row.unrecognizedTip", defaultValue: "Unrecognized status — schema 정식 표기 아님"))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 5)
        .background(rowBackground)
        .overlay(alignment: .leading) {
            if isSelected {
                Rectangle()
                    .fill(BVColor.accent)
                    .frame(width: 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpen(task) }
        .onHover { rowHover = $0 }
        // HTML positionPopover:
        //   state(status) → anchor `.ind`, left = r.left (아이콘 left edge)
        //   priority      → anchor `.pri`, left = r.right - er.width (아이콘 right)
        // 둘 다 row가 아니라 각 아이콘 버튼 자체가 anchor. 각 button에 직접
        // .panelPopover를 붙여 그렇게 동작한다.
        .contextMenu {
            Button(String(localized: "task.row.open", defaultValue: "Open")) {
                onOpen(task)
            }
            Divider()
            Button(String(localized: "task.row.changePriority", defaultValue: "Change priority…")) {
                showPriorityPicker = true
            }
        }
    }

    private var rowBackground: Color {
        // HTML: `.item.selected { background: selected-bg; }`
        //       `.item:hover { background: rgba(0,0,0,0.025); }`
        // selected가 hover보다 우선.
        if isSelected { return BVColor.accent.opacity(0.18) }
        if rowHover { return BVColor.bgHover }
        return Color.clear
    }

    private var isCompleted: Bool {
        guard let s = task.status else { return false }
        return s == .done || s == .canceled
    }

    @ViewBuilder
    private var statusButton: some View {
        // Group + frame + contentShape makes the full 14×14 box hit-testable.
        // Without contentShape, Button's plain hit region is the glyph's
        // visible shape — stroked-outline statuses (todo) and the thin
        // PriorityBars expose only a few points of tappable area.
        Button(action: { showStatusPicker = true }) {
            Group {
                if let status = task.status {
                    StatusGlyph(status: status)
                } else if task.unrecognizedStatusRaw != nil {
                    unknownGlyph
                } else {
                    Circle()
                        .strokeBorder(BVColor.fgFaint, style: StrokeStyle(lineWidth: 1, dash: [2, 1.4]))
                }
            }
            .frame(width: 14, height: 14)
            .scaleEffect(statusHover ? 1.08 : 1.0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { statusHover = $0 }
        .panelPopover(isPresented: $showStatusPicker, alignment: .leading) {
            TaskStatusPicker(current: task.status) { newStatus in
                onChangeStatus(task, newStatus)
                showStatusPicker = false
            }
        }
    }

    @ViewBuilder
    private var priorityButton: some View {
        Button(action: { showPriorityPicker = true }) {
            TaskPriorityIcon(priority: task.priority)
                .frame(width: 14, height: 14)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(priorityHover ? BVColor.bgHover : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { priorityHover = $0 }
        .panelPopover(isPresented: $showPriorityPicker, alignment: .trailing) {
            TaskPriorityPicker(current: task.priority) { newPriority in
                onChangePriority(task, newPriority)
                showPriorityPicker = false
            }
        }
    }

    private var unknownGlyph: some View {
        ZStack {
            Circle().fill(BVColor.fgFaint.opacity(0.3))
            Text("?")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(BVColor.fgMute)
        }
    }

    private func dueLabel(_ d: Date) -> String {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let target = cal.startOfDay(for: d)
        let days = cal.dateComponents([.day], from: today, to: target).day ?? 0
        if abs(days) >= 7 {
            let w = days / 7
            return "\(w)w"
        }
        return "\(days)d"
    }

    private func dueWeight(_ d: Date) -> Font.Weight {
        // HTML: .due.over (음수 days) = weight 600. .due.soon (0–1d) = weight 500.
        // 그 외 default. status에 따른 분기 아님 — over면 status 무관 다 볼드.
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let target = cal.startOfDay(for: d)
        let days = cal.dateComponents([.day], from: today, to: target).day ?? 0
        return days < 0 ? .semibold : .regular
    }

    private func dueColor(_ d: Date) -> Color {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let target = cal.startOfDay(for: d)
        let days = cal.dateComponents([.day], from: today, to: target).day ?? 0
        // HTML 디자인: 0–1d "soon" 과 -d "over" 모두 빨강. 두 경우 모두 priorityUrgent.
        // 굵기는 dueLabel 호출부에서 분기.
        if days <= 1 { return BVColor.priorityUrgent }
        return BVColor.fgFaint
    }
}

/// Lightweight wrapper around the existing date picker popover for task due dates.
struct TaskDuePopover: View {
    let current: Date?
    let onSelect: (Date?) -> Void

    @State private var selected: Date

    init(current: Date?, onSelect: @escaping (Date?) -> Void) {
        self.current = current
        self.onSelect = onSelect
        _selected = State(initialValue: current ?? Date())
    }

    var body: some View {
        VStack(spacing: 0) {
            DatePicker("", selection: $selected, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding(.horizontal, 6).padding(.top, 6).padding(.bottom, 4)
            Divider()
            HStack {
                Button(String(localized: "task.due.clear", defaultValue: "Clear")) {
                    onSelect(nil)
                }
                .buttonStyle(.plain)
                .foregroundColor(BVColor.fgMute)
                .font(.system(size: 11.5))
                Spacer(minLength: 8)
                Button(String(localized: "task.due.set", defaultValue: "Set")) {
                    onSelect(selected)
                }
                .buttonStyle(.plain)
                .foregroundColor(BVColor.accent)
                .font(.system(size: 11.5, weight: .semibold))
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
        }
        .fixedSize()
        .background(BVColor.bg)
    }
}
