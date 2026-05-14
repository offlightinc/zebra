import SwiftUI

/// Two-step filter popover state. Both steps share the same anchor (the
/// Filter button) so the popover transitions in place rather than moving.
enum TaskFilterPopoverStep: Equatable {
    case field
    case value(TaskFilterField)
}

/// Top toolbar: `+ Filter` (left) + `Group: …` (right).
struct TaskListToolbar: View {
    let groupBy: TaskGroupBy
    let existingFilterFields: Set<TaskFilterField>
    let availableOwners: [String]
    @Binding var filterStep: TaskFilterPopoverStep?
    let currentFilter: (TaskFilterField) -> TaskFilter
    let onPickGroupBy: (TaskGroupBy) -> Void
    let onPickField: (TaskFilterField) -> Void
    let onChangeFilterValues: (TaskFilter) -> Void
    let onCloseFilter: () -> Void

    @State private var showGroupByMenu = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: {
                if filterStep == nil { filterStep = .field } else { filterStep = nil }
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 10))
                    Text(String(localized: "task.toolbar.filter", defaultValue: "Filter"))
                        .font(.system(size: 11.5))
                }
                .foregroundColor(BVColor.fgMute)
                .padding(.horizontal, 7).padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .panelPopover(isPresented: filterPopoverPresented, alignment: .leading) {
                filterPopoverContent
            }
            Spacer()
            Button(action: { showGroupByMenu = true }) {
                HStack(spacing: 5) {
                    Text(String(localized: "task.toolbar.group", defaultValue: "Group"))
                        .font(.system(size: 11.5))
                    Text(groupBy.label)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(BVColor.fg)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                        .foregroundColor(BVColor.fgFaint)
                }
                .foregroundColor(BVColor.fgMute)
                .padding(.horizontal, 7).padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .panelPopover(isPresented: $showGroupByMenu, alignment: .trailing) {
                TaskGroupByPicker(current: groupBy) { opt in
                    showGroupByMenu = false
                    onPickGroupBy(opt)
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(BVColor.bg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(BVColor.border).frame(height: 1)
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
            TaskFilterFieldPicker(existingFields: existingFilterFields) { field in
                onPickField(field)
                filterStep = .value(field)
            }
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
