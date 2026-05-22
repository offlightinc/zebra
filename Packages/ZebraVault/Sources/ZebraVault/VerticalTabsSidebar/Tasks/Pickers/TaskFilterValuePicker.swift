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
    /// `true` 일 때 row 클릭은 토글이 아니라 "이 행만 선택" replace 동작. 같은 행을
    /// 다시 클릭하면 선택 해제. 호출 직후 `onCommit` 으로 호출 사이트가 popover 를
    /// 닫게 한다. "내 것" toolbar 처럼 한 명만 보고 싶을 때 사용.
    let singleSelect: Bool
    let onCommit: (() -> Void)?

    @State private var workingValues: [String]
    @State private var workingOp: TaskFilterOp

    init(
        field: TaskFilterField,
        current: TaskFilter,
        availableOwners: [String],
        onChange: @escaping (TaskFilter) -> Void,
        compact: Bool = false,
        singleSelect: Bool = false,
        onCommit: (() -> Void)? = nil
    ) {
        self.field = field
        self.current = current
        self.availableOwners = availableOwners
        self.onChange = onChange
        self.compact = compact
        self.singleSelect = singleSelect
        self.onCommit = onCommit
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
            // single-select 는 row 배경 틴트로만 표시 — checkmark 는 multi-select 의미라
            // single-select 에 두면 체크박스처럼 보여 의미가 모호해진다.
            multiSelectChecked: singleSelect ? false : selected
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
                // PickerRow 의 outer 14×14 frame 은 슬롯 크기만 잡고 child 를 늘리지
                // 않으므로 헬퍼가 size: 14 로 자체 프레임을 보장한다.
                PersonAvatarGlyph(slug: raw, size: 14)
            }
        }
    }

    private func toggle(_ raw: String) {
        if singleSelect {
            // 같은 행 재클릭은 해제로 취급해 "선택 비우기" 경로를 row 만으로 커버.
            if workingValues == [raw] {
                workingValues = []
            } else {
                workingValues = [raw]
            }
            // single-select 모드는 op 토글 UI 가 없으니 `.is` 로 정규화 — 이전 세션의
            // `.isNot` 잔재가 새로운 선택으로 덮어써지지 않고 살아남는 걸 막는다.
            workingOp = .is
            pushChange()
            onCommit?()
            return
        }
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
