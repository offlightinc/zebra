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
        TaskPickerContainer(
            title: "\(field.label) \(workingOp.symbol)",
            width: 220
        ) {
            valueRows

            Divider()
                .padding(.vertical, 4)

            Button(action: toggleOp) {
                HStack {
                    // ko/ja 번역은 xcstrings에 들어있다 (task.filter.useIs 등).
                    // defaultValue는 영어 표준 — 런타임에 시스템 언어에 맞춰
                    // 적절한 번역으로 치환된다.
                    Text(workingOp == .is
                        ? String(localized: "task.filter.useIsNot", defaultValue: "Use \"is not\" operator")
                        : String(localized: "task.filter.useIs", defaultValue: "Use \"is\" operator"))
                        .font(.system(size: 11.5))
                        .foregroundColor(BVColor.fgMute)
                    Spacer()
                }
                .padding(.horizontal, 8).frame(height: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private var valueRows: some View {
        switch field {
        case .status:
            // HTML 디자인 filter 옵션: backlog/todo/inprogress/blocked/done 5개만.
            let opts: [(String, String)] = BrainTaskStatus.primaryCases.map {
                ($0.rawValue, $0.localizedLabel)
            } + [("__unrecognized__", String(localized: "task.group.unrecognized", defaultValue: "Unrecognized"))]
            ForEach(opts, id: \.0) { (raw, label) in
                row(raw: raw, label: label)
            }
        case .priority:
            let opts: [(String, String)] = [
                (BrainPriority.urgent.rawValue, BrainPriority.urgent.localizedLabel),
                (BrainPriority.high.rawValue,   BrainPriority.high.localizedLabel),
                (BrainPriority.medium.rawValue, BrainPriority.medium.localizedLabel),
                (BrainPriority.low.rawValue,    BrainPriority.low.localizedLabel),
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
        return TaskPickerRow(
            glyph: {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12))
                    .foregroundColor(selected ? BVColor.accent : BVColor.fgFaint)
            },
            label: label,
            isCurrent: selected,
            keyLabel: nil,
            action: { toggle(raw) }
        )
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
