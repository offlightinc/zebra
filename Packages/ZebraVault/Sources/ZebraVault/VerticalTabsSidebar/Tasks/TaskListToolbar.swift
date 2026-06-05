import SwiftUI

/// Two-step filter popover state for the Filter button. The "내 것" toolbar
/// entry uses its own state (`showMyOwnerMenu`) and does not flow through here.
enum TaskFilterPopoverStep: Equatable {
    case field
    case value(TaskFilterField)
}

/// Top toolbar: `+ Filter` + `Sort` (left) + `Group: …` + `내 것` toggle (right).
struct TaskListToolbar: View {
    let groupBy: TaskGroupBy
    let sort: TaskSort
    let sortDirection: TaskSortDirection
    let myOwnerFilter: TaskFilter?
    let existingFilterFields: Set<TaskFilterField>
    let availableOwners: [String]
    @Binding var filterStep: TaskFilterPopoverStep?
    @Binding var showMyOwnerMenu: Bool
    let currentFilter: (TaskFilterField) -> TaskFilter
    let onPickGroupBy: (TaskGroupBy) -> Void
    let onPickSort: (TaskSort) -> Void
    let onPickField: (TaskFilterField) -> Void
    let onChangeFilterValues: (TaskFilter) -> Void
    let onChangeMyOwnerFilter: (TaskFilter?) -> Void
    let onCloseFilter: () -> Void

    @State private var showGroupByMenu = false
    @State private var showSortMenu = false
    @State private var filterHover = false
    @State private var sortHover = false
    @State private var groupHover = false
    @State private var myHover = false

    var body: some View {
        HStack(spacing: 0) {
            filterButton
            sortButton
            groupButton
            Spacer(minLength: 0)
            myToggleButton
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(BVColor.bg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(BVColor.border).frame(height: 1)
        }
    }

    private var isMyActive: Bool {
        guard let mf = myOwnerFilter else { return false }
        return !mf.values.isEmpty
    }

    /// "내 것" picker 는 single-select 라 아바타로 노출 가능한 경우는 값이 한 개이고
    /// `__unassigned__` 가 아닐 때뿐. op 가 `.isNot` 이면 의미가 반대(그 사람 제외)
    /// 이므로 아바타로 표시하면 오해를 부른다 — fallback silhouette 으로 돌린다.
    /// 그 외(0개·미지정·legacy multi 잔재)도 마찬가지.
    private var selectedOwnerSlug: String? {
        guard let mf = myOwnerFilter,
              mf.op == .is,
              mf.values.count == 1,
              let v = mf.values.first,
              v != "__unassigned__"
        else { return nil }
        return v
    }

    private var filterButton: some View {
        Button(action: {
            if filterStep == nil {
                filterStep = .field
            } else {
                // 닫기 경로에서도 binding setter처럼 빈 칩을 정리해야 한다.
                // (단순히 filterStep=nil만 하면 binding setter가 안 거쳐서
                // 값 없이 추가된 필터가 (none) 칩으로 남는다.)
                onCloseFilter()
                filterStep = nil
            }
        }) {
            HStack(spacing: 5) {
                FilterFunnelIcon()
                    .frame(width: 12, height: 12)
                Text(String(localized: "task.toolbar.filter", defaultValue: "Filter"))
                    .font(.system(size: 11.5))
            }
            .foregroundColor(BVColor.fgMute)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(filterHover ? BVColor.bgHover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { filterHover = $0 }
        .panelPopover(isPresented: filterPopoverPresented, alignment: .leading) {
            filterPopoverContent
        }
    }

    private var sortButton: some View {
        Button(action: { showSortMenu = true }) {
            HStack(spacing: 5) {
                Text(String(localized: "task.toolbar.sort", defaultValue: "Sort"))
                    .font(.system(size: 11.5))
                    .foregroundColor(BVColor.fgMute)
                Text(sort.label)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(BVColor.fg)
                    .lineLimit(1)
                SortDirectionGlyph(direction: sortDirection)
                    .foregroundColor(BVColor.fgMute)
                    .frame(width: 7, height: 12)
            }
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(sortHover ? BVColor.bgHover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { sortHover = $0 }
        .panelPopover(isPresented: $showSortMenu, alignment: .leading) {
            TaskSortPicker(current: sort, direction: sortDirection) { opt in
                onPickSort(opt)
            }
        }
    }

    private var myToggleButton: some View {
        Button(action: { showMyOwnerMenu = true }) {
            Group {
                if let slug = selectedOwnerSlug {
                    PersonAvatarGlyph(slug: slug, size: 16)
                } else {
                    Image(systemName: isMyActive ? "person.crop.circle.fill" : "person.crop.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(isMyActive ? BVColor.accent : BVColor.fgMute)
                }
            }
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(myHover ? BVColor.bgHover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { myHover = $0 }
        .panelPopover(isPresented: $showMyOwnerMenu, alignment: .trailing) {
            TaskFilterValuePicker(
                field: .owner,
                current: myOwnerFilter ?? TaskFilter(field: .owner, op: .is, values: []),
                availableOwners: availableOwners,
                onChange: { updated in
                    onChangeMyOwnerFilter(updated.values.isEmpty ? nil : updated)
                },
                compact: true,
                singleSelect: true,
                onCommit: { showMyOwnerMenu = false }
            )
        }
        .safeHelp(
            String(localized: "task.toolbar.my.tooltip", defaultValue: "Show my tasks")
        )
    }

    private var groupButton: some View {
        Button(action: { showGroupByMenu = true }) {
            HStack(spacing: 5) {
                Text(String(localized: "task.toolbar.group", defaultValue: "Group"))
                    .font(.system(size: 11.5))
                    .foregroundColor(BVColor.fgMute)
                Text(groupBy.label)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(BVColor.fg)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                // 가로:세로 약 1.8:1 비율의 납작한 down-triangle. macOS SF Pro의
                // "▾" U+25BE는 정사각에 가까워 HTML 디자인의 납작한 비율과 다르다.
                FlatDownCarat()
                    .fill(BVColor.fgMute)
                    .frame(width: 4.5, height: 2.5)
                    .padding(.leading, 3)
            }
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(groupHover ? BVColor.bgHover : Color.clear)
            )
            .contentShape(Rectangle())
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
        .onHover { groupHover = $0 }
        .panelPopover(isPresented: $showGroupByMenu, alignment: .trailing) {
            TaskGroupByPicker(current: groupBy) { opt in
                showGroupByMenu = false
                onPickGroupBy(opt)
            }
        }
    }

    private var filterPopoverPresented: Binding<Bool> {
        Binding(
            get: { filterStep != nil },
            set: { newValue in
                if !newValue {
                    onCloseFilter()
                    filterStep = nil
                }
            }
        )
    }

    @ViewBuilder
    private var filterPopoverContent: some View {
        switch filterStep {
        case .field, .none:
            TaskFilterFieldPicker(
                existingFields: existingFilterFields,
                onSelect: { field in
                    onPickField(field)
                    filterStep = .value(field)
                }
            )
        case .value(let field):
            // `.id(field)` forces a fresh view instance per field so that
            // TaskFilterValuePicker's @State (workingValues/workingOp) does
            // not leak across Status → Priority → Owner transitions.
            TaskFilterValuePicker(
                field: field,
                current: currentFilter(field),
                availableOwners: availableOwners,
                onChange: onChangeFilterValues
            )
            .id(field)
        }
    }
}

private struct SortDirectionGlyph: Shape {
    let direction: TaskSortDirection

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let centerX = rect.midX
        let shaftTop = rect.minY + 2
        let shaftBottom = rect.maxY - 2
        let headHalfWidth: CGFloat = 1.7
        let headHeight: CGFloat = 2.2

        switch direction {
        case .ascending:
            path.move(to: CGPoint(x: centerX, y: shaftBottom))
            path.addLine(to: CGPoint(x: centerX, y: shaftTop))
            path.move(to: CGPoint(x: centerX - headHalfWidth, y: shaftTop + headHeight))
            path.addLine(to: CGPoint(x: centerX, y: shaftTop))
            path.addLine(to: CGPoint(x: centerX + headHalfWidth, y: shaftTop + headHeight))
        case .descending:
            path.move(to: CGPoint(x: centerX, y: shaftTop))
            path.addLine(to: CGPoint(x: centerX, y: shaftBottom))
            path.move(to: CGPoint(x: centerX - headHalfWidth, y: shaftBottom - headHeight))
            path.addLine(to: CGPoint(x: centerX, y: shaftBottom))
            path.addLine(to: CGPoint(x: centerX + headHalfWidth, y: shaftBottom - headHeight))
        }

        return path.strokedPath(.init(lineWidth: 1, lineCap: .round, lineJoin: .round))
    }
}

/// 가로로 납작한 down-pointing triangle. 채워진 SF Symbol과 텍스트 글리프
/// 모두 정사각에 가까워서, HTML 디자인의 비율을 그대로 옮기지 못한다.
struct FlatDownCarat: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// 3-막대 필터 아이콘. HTML 베이스(viewBox 14×14, 막대 길이 10/7/3) 대비:
/// 1) 막대 길이 15% 축소 (10→8.5, 7→5.95, 3→2.55) 후
/// 2) 마지막 막대를 "점보다 조금 긴" 수준(1.5pt)으로 더 줄이고
/// 3) 그 비율에 맞춰 위/중간 재산정 (8.5 / 5 / 1.5)
/// 4) 막대간 간격을 넓힘 (y 3/7/11 → 2.5/7/11.5)
struct FilterFunnelIcon: View {
    var body: some View {
        Canvas { ctx, size in
            let scale = size.width / 14.0
            let stroke = StrokeStyle(lineWidth: 1.6 * scale, lineCap: .round)
            let lines: [(x1: CGFloat, x2: CGFloat, y: CGFloat)] = [
                (2.75, 11.25, 2.5),  // 위: 8.5pt
                (4.5,  9.5,   7),    // 중간: 5pt
                (6.25, 7.75,  11.5), // 아래: 1.5pt (점에 가까움)
            ]
            for line in lines {
                var path = Path()
                path.move(to: CGPoint(x: line.x1 * scale, y: line.y * scale))
                path.addLine(to: CGPoint(x: line.x2 * scale, y: line.y * scale))
                ctx.stroke(path, with: .color(BVColor.fgMute), style: stroke)
            }
        }
    }
}
