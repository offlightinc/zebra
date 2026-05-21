import SwiftUI

/// Step 2 of the filter flow: pick values for a field. Multi-select.
/// "Use is/is not 연산자" toggle at the bottom. Empty selection on close
/// → caller removes the filter.
struct TaskFilterValuePicker: View {
    let field: TaskFilterField
    let current: TaskFilter
    let availableOwners: [String]
    let onChange: (TaskFilter) -> Void
    /// `true` 일 때 헤더 ("담당자 =") 와 하단 op 토글을 숨긴다. "내 것" toolbar
    /// 진입처럼 op 가 항상 `.is` 고정인 컨텍스트에서 사용.
    let compact: Bool

    @State private var workingValues: [String]
    @State private var workingOp: TaskFilterOp

    init(
        field: TaskFilterField,
        current: TaskFilter,
        availableOwners: [String],
        onChange: @escaping (TaskFilter) -> Void,
        compact: Bool = false
    ) {
        self.field = field
        self.current = current
        self.availableOwners = availableOwners
        self.onChange = onChange
        self.compact = compact
        _workingValues = State(initialValue: current.values)
        _workingOp = State(initialValue: current.op)
    }

    var body: some View {
        PickerContainer(
            title: compact ? nil : "\(field.label) \(workingOp.symbol)",
            width: 200
        ) {
            valueRows

            if !compact {
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

    @ViewBuilder
    private func row(raw: String, label: String) -> some View {
        let selected = workingValues.contains(raw)
        PickerRow(
            glyph: { glyphView(raw: raw) },
            label: label,
            isCurrent: selected,
            keyLabel: nil,
            action: { toggle(raw) },
            multiSelectChecked: selected
        )
    }

    /// HTML 디자인의 svgMap 대응. status는 StatusGlyph, priority는 TaskPriorityIcon,
    /// owner는 첫 글자 아바타. pseudo-option(`__unrecognized__` / `__none__` /
    /// `__unassigned__`)은 fallback glyph로 처리.
    @ViewBuilder
    private func glyphView(raw: String) -> some View {
        switch field {
        case .status:
            if raw == "__unrecognized__" {
                StatusGlyph(shape: .unknown)
            } else if let status = BrainTaskStatus(rawValue: raw) {
                StatusGlyph(shape: status.glyphShape)
            }
        case .priority:
            if raw == "__none__" {
                TaskNoPriorityGlyph()
            } else if let priority = BrainPriority(rawValue: raw) {
                TaskPriorityIcon(priority: priority)
            } else {
                EmptyView()
            }
        case .owner:
            if raw == "__unassigned__" {
                Image(systemName: "person.slash")
                    .font(.system(size: 11))
                    .foregroundColor(BVColor.fgMute)
            } else {
                // PickerRow의 outer 14×14 frame은 슬롯 크기만 잡고 child를 늘리지 않으므로,
                // Text+Circle background 조합은 inner frame으로 자체 크기 보장해야 함.
                Text(String(raw.prefix(1)).uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 14, height: 14)
                    .background(Circle().fill(BrainPersonColor.color(for: raw)))
            }
        }
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
