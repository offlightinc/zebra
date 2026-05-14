import SwiftUI

/// Step 2 of the filter flow: pick values for a field. Multi-select.
/// "Use is/is not 연산자" toggle at the bottom. Empty selection on close
/// → caller removes the filter.
struct TaskFilterValuePicker: View {
    let field: TaskFilterField
    let current: TaskFilter
    let availableOwners: [String]
    let onChange: (TaskFilter) -> Void

    @State private var workingValues: [String]
    @State private var workingOp: TaskFilterOp

    init(
        field: TaskFilterField,
        current: TaskFilter,
        availableOwners: [String],
        onChange: @escaping (TaskFilter) -> Void
    ) {
        self.field = field
        self.current = current
        self.availableOwners = availableOwners
        self.onChange = onChange
        _workingValues = State(initialValue: current.values)
        _workingOp = State(initialValue: current.op)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("\(field.label) \(workingOp.symbol)")
                .font(.system(size: 10.5))
                .fontWeight(.semibold)
                .foregroundColor(BVColor.fgFaint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 4)

            valueRows

            Divider()

            Button(action: toggleOp) {
                HStack {
                    Text(workingOp == .is
                        ? String(localized: "task.filter.useIsNot", defaultValue: "Use \"is not\" operator")
                        : String(localized: "task.filter.useIs", defaultValue: "Use \"is\" operator"))
                        .font(.system(size: 11.5))
                        .foregroundColor(BVColor.fgMute)
                    Spacer()
                }
                .padding(.horizontal, 10).frame(height: 26)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .frame(width: 200)
        .background(BVColor.bgElev)
    }

    @ViewBuilder
    private var valueRows: some View {
        switch field {
        case .status:
            let opts: [(String, String)] = [
                (BrainTaskStatus.todo.rawValue,      TaskListViewModel.statusLabel(.todo)),
                (BrainTaskStatus.doing.rawValue,     TaskListViewModel.statusLabel(.doing)),
                (BrainTaskStatus.blocked.rawValue,   TaskListViewModel.statusLabel(.blocked)),
                (BrainTaskStatus.waiting.rawValue,   TaskListViewModel.statusLabel(.waiting)),
                (BrainTaskStatus.completed.rawValue, TaskListViewModel.statusLabel(.completed)),
                (BrainTaskStatus.canceled.rawValue,  TaskListViewModel.statusLabel(.canceled)),
                ("__unrecognized__", String(localized: "task.group.unrecognized", defaultValue: "Unrecognized")),
            ]
            ForEach(opts, id: \.0) { (raw, label) in
                row(raw: raw, label: label)
            }
        case .priority:
            let opts: [(String, String)] = [
                (BrainPriority.urgent.rawValue, TaskListViewModel.priorityLabel(.urgent)),
                (BrainPriority.high.rawValue,   TaskListViewModel.priorityLabel(.high)),
                (BrainPriority.normal.rawValue, TaskListViewModel.priorityLabel(.normal)),
                (BrainPriority.low.rawValue,    TaskListViewModel.priorityLabel(.low)),
                ("__none__", String(localized: "task.priority.none", defaultValue: "No priority")),
            ]
            ForEach(opts, id: \.0) { (raw, label) in
                row(raw: raw, label: label)
            }
        case .owner:
            let opts: [(String, String)] =
                [("__unassigned__", String(localized: "task.group.unassigned", defaultValue: "Unassigned"))]
                + availableOwners.map { ($0, $0) }
            ForEach(opts, id: \.0) { (raw, label) in
                row(raw: raw, label: label)
            }
        }
    }

    private func row(raw: String, label: String) -> some View {
        let selected = workingValues.contains(raw)
        return Button(action: { toggle(raw) }) {
            HStack(spacing: 8) {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12))
                    .foregroundColor(selected ? BVColor.accent : BVColor.fgFaint)
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(BVColor.fg)
                Spacer()
            }
            .padding(.horizontal, 10).frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ raw: String) {
        if let idx = workingValues.firstIndex(of: raw) {
            workingValues.remove(at: idx)
        } else {
            workingValues.append(raw)
        }
        pushChange()
    }

    private func toggleOp() {
        workingOp = (workingOp == .is) ? .isNot : .is
        pushChange()
    }

    private func pushChange() {
        var copy = current
        copy.values = workingValues
        copy.op = workingOp
        onChange(copy)
    }
}
