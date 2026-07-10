import SwiftUI

/// Two-step filter popover state for the Filter button.
enum TaskFilterPopoverStep: Equatable {
    case field
    case value(TaskFilterField)
}

/// Task view controls. View mode stays on the left; filtering/sorting/grouping
/// stay right-aligned. `ViewThatFits` swaps the text controls for icon-only
/// controls before a narrow sidebar can overlap or clip them.
struct TaskListToolbar: View {
    let viewMode: TaskListViewMode
    let showsSortAndGroup: Bool
    let groupBy: TaskGroupBy
    let sort: TaskSort
    let sortDirection: TaskSortDirection
    let existingFilterFields: Set<TaskFilterField>
    let availableOwners: [String]
    @Binding var filterStep: TaskFilterPopoverStep?
    let currentFilter: (TaskFilterField) -> TaskFilter
    let onPickViewMode: (TaskListViewMode) -> Void
    let onPickGroupBy: (TaskGroupBy) -> Void
    let onPickSort: (TaskSort) -> Void
    let onPickField: (TaskFilterField) -> Void
    let onChangeFilterValues: (TaskFilter) -> Void
    let onCloseFilter: () -> Void

    @State private var showGroupByMenu = false
    @State private var showSortMenu = false
    @State private var filterHover = false
    @State private var sortHover = false
    @State private var groupHover = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            toolbarRow(compact: false)
            toolbarRow(compact: true)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(BVColor.bg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(BVColor.border).frame(height: 1)
        }
    }

    private func toolbarRow(compact: Bool) -> some View {
        HStack(spacing: 0) {
            viewModePicker
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 8)
            HStack(spacing: 0) {
                filterButton(compact: compact)
                if showsSortAndGroup {
                    sortButton(compact: compact)
                    groupButton(compact: compact)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity)
    }

    private func filterButton(compact: Bool) -> some View {
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
                if !compact {
                    Text(String(localized: "task.toolbar.filter", defaultValue: "Filter"))
                        .font(.system(size: 11.5))
                }
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
        .safeHelp(String(localized: "task.toolbar.filter", defaultValue: "Filter"))
        .accessibilityIdentifier("VerticalTabsSidebar.Tasks.filter")
    }

    private func sortButton(compact: Bool) -> some View {
        Button(action: { showSortMenu = true }) {
            Group {
                if compact {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(BVColor.fgMute)
                } else {
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
                }
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
        .safeHelp(String(localized: "task.toolbar.sort", defaultValue: "Sort"))
        .accessibilityIdentifier("VerticalTabsSidebar.Tasks.sort")
    }

    private func groupButton(compact: Bool) -> some View {
        Button(action: { showGroupByMenu = true }) {
            Group {
                if compact {
                    Image(systemName: "rectangle.3.group")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(BVColor.fgMute)
                } else {
                    HStack(spacing: 5) {
                        Text(String(localized: "task.toolbar.group", defaultValue: "Group"))
                            .font(.system(size: 11.5))
                            .foregroundColor(BVColor.fgMute)
                        Text(groupBy.label)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(BVColor.fg)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                        FlatDownCarat()
                            .fill(BVColor.fgMute)
                            .frame(width: 4.5, height: 2.5)
                            .padding(.leading, 3)
                    }
                }
            }
            .foregroundColor(BVColor.fgMute)
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
        .safeHelp(String(localized: "task.toolbar.group", defaultValue: "Group"))
        .accessibilityIdentifier("VerticalTabsSidebar.Tasks.group")
    }

    private var viewModePicker: some View {
        HStack(spacing: 2) {
            viewModeButton(.all, systemName: "list.bullet")
            viewModeButton(.todayPlan, systemName: "calendar")
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(BVColor.bgElev)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(BVColor.border, lineWidth: 1)
        )
    }

    private func viewModeButton(_ mode: TaskListViewMode, systemName: String) -> some View {
        Button {
            onPickViewMode(mode)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(viewMode == mode ? BVColor.fg : BVColor.fgMute)
                .frame(width: 24, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(viewMode == mode ? BVColor.bgHover : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .safeHelp(mode.label)
        .accessibilityLabel(mode.label)
        .accessibilityIdentifier("VerticalTabsSidebar.Tasks.viewMode.\(mode.rawValue)")
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
