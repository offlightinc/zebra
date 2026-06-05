import SwiftUI

struct TaskListView: View {
    @ObservedObject var store: TaskFileListStore
    let activePaths: Set<String>
    let onSelectFile: (String) -> Void
    @StateObject private var viewModel = TaskListViewModel()
    @State private var filterStep: TaskFilterPopoverStep?
    @State private var showMyOwnerMenu = false

    var body: some View {
        // Read store.tasks directly in body so SwiftUI's ObservedObject
        // tracking definitively captures the subscription. Reading inside
        // a computed property was unreliable in this context — file-watcher
        // reassignments invalidated the view, but in-place mutations from
        // `replace()` did not.
        let tasksSnapshot = store.tasks
        return VStack(spacing: 0) {
            collapseAllToolbar(tasks: tasksSnapshot)
            TaskListToolbar(
                groupBy: viewModel.groupBy,
                sort: viewModel.sort,
                sortDirection: viewModel.sortDirection,
                myOwnerFilter: viewModel.myOwnerFilter,
                existingFilterFields: Set(viewModel.filters.map(\.field)),
                availableOwners: availableOwners,
                filterStep: $filterStep,
                showMyOwnerMenu: $showMyOwnerMenu,
                currentFilter: { field in
                    viewModel.filters.first(where: { $0.field == field })
                        ?? TaskFilter(field: field, op: .is, values: [])
                },
                onPickGroupBy: { viewModel.groupBy = $0 },
                onPickSort: { viewModel.pickSort($0) },
                onPickField: { field in
                    if !viewModel.filters.contains(where: { $0.field == field }) {
                        viewModel.filters.append(TaskFilter(field: field, op: .is, values: []))
                    }
                },
                onChangeFilterValues: { updated in
                    viewModel.setFilter(updated)
                },
                onChangeMyOwnerFilter: { updated in
                    viewModel.myOwnerFilter = updated
                },
                onCloseFilter: {
                    // Empty values → remove the chip on dismiss.
                    if case .value(let f) = filterStep,
                       let idx = viewModel.filters.firstIndex(where: { $0.field == f }),
                       viewModel.filters[idx].values.isEmpty {
                        viewModel.filters.remove(at: idx)
                    }
                }
            )
            .frame(height: ZebraSidebarMetrics.secondRowHeight)
            if !viewModel.filters.isEmpty {
                chipRow
            }
            listContent(tasks: tasksSnapshot)
        }
        .background(BVColor.bg)
        .onAppear {
            viewModel.bindPersistence(rootPath: store.rootPath)
        }
        .onChange(of: store.rootPath) { newRootPath in
            viewModel.bindPersistence(rootPath: newRootPath)
        }
    }

    // 같은 위치/모양/단축키 의도로 Goals 의 collapseAllToolbar 와 1:1 — 모드
    // 전환 시 첫 줄이 정합. canCollapse 조건은 "현재 그룹이 한 개 이상이고 그
    // 중 펼친 게 한 개라도 있을 때". 그룹이 0개 (no tasks / no grouping=all 만)
    // 인 경우는 비활성화하지만 자리는 유지 → 첫 줄이 점프 안 함.
    private func collapseAllToolbar(tasks: [TaskItem]) -> some View {
        let displayTasks = viewModel.displayTasks(from: tasks)
        let groups = TaskListViewModel.groupTasks(displayTasks, by: viewModel.groupBy)
        let allCollapsed = !groups.isEmpty && groups.allSatisfy { viewModel.collapsedSections.contains($0.key.raw) }
        let canCollapse = store.rootPath != nil && !groups.isEmpty && !allCollapsed
        return HStack(spacing: 0) {
            Spacer(minLength: 0)
            Button {
                viewModel.collapsedSections = Set(groups.map { $0.key.raw })
            } label: {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canCollapse)
            .opacity(canCollapse ? 1 : 0)
            .safeHelp(
                String(localized: "verticalTabsSidebar.tasks.collapseAll.tooltip", defaultValue: "Collapse all")
            )
            .accessibilityLabel(
                String(localized: "verticalTabsSidebar.tasks.collapseAll.accessibilityLabel", defaultValue: "Collapse all")
            )
            .accessibilityIdentifier("VerticalTabsSidebar.Tasks.collapseAll")
        }
        .padding(.horizontal, 6)
        .frame(height: ZebraSidebarMetrics.firstRowTopOffset)
    }

    @ViewBuilder
    private func listContent(tasks: [TaskItem]) -> some View {
        if store.rootPath == nil {
            placeholder(String(localized: "task.list.empty.noVault", defaultValue: "No vault selected"))
        } else if tasks.isEmpty && store.isScanning {
            VStack {
                Spacer()
                ProgressView().controlSize(.small)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = store.lastError {
            placeholder(String(localized: "task.list.empty.error", defaultValue: "Failed to load: \(error)"))
        } else if tasks.isEmpty {
            placeholder(String(localized: "task.list.empty.noTasks", defaultValue: "No tasks in vault"))
        } else if viewModel.displayTasks(from: tasks).isEmpty {
            placeholder(String(localized: "task.list.empty.noMatches", defaultValue: "No matching tasks"))
        } else {
            listScrollView(tasks: tasks)
        }
    }

    private func placeholder(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var availableOwners: [String] {
        Array(Set(store.tasks.compactMap(\.ownerSlug))).sorted()
    }

    private var chipRow: some View {
        // HTML: `.chiprow { display: flex; flex-wrap: wrap; gap: 5px; }`
        // 칩이 컨테이너 너비를 넘으면 줄바꿈된다 (가로 스크롤 X).
        TaskChipFlowLayout(spacing: 5) {
            ForEach(viewModel.filters) { f in
                TaskFilterChipView(
                    filter: f,
                    onEdit: { filterStep = .value(f.field) },
                    onRemove: { viewModel.removeFilter(field: f.field) }
                )
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BVColor.bg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(BVColor.border).frame(height: 1)
        }
    }

    private func listScrollView(tasks: [TaskItem]) -> some View {
        let displayTasks = viewModel.displayTasks(from: tasks)
        let groups = TaskListViewModel.groupTasks(displayTasks, by: viewModel.groupBy)
        return ScrollView {
            LazyVStack(spacing: 0, pinnedViews: []) {
                ForEach(groups) { group in
                    SidebarSectionHeader(
                        label: group.key.label,
                        count: group.items.count,
                        isCollapsed: viewModel.collapsedSections.contains(group.key.raw),
                        onToggle: {
                            if viewModel.collapsedSections.contains(group.key.raw) {
                                viewModel.collapsedSections.remove(group.key.raw)
                            } else {
                                viewModel.collapsedSections.insert(group.key.raw)
                            }
                        }
                    )
                    .equatable()
                    if !viewModel.collapsedSections.contains(group.key.raw) {
                        // id: \.self forces a new row instance when any TaskItem
                        // field changes (including status). Identifiable's
                        // task.id = absolutePath keeps the row stable across
                        // status changes, which is what we DON'T want — SwiftUI
                        // then skips body re-evaluation and the status glyph
                        // stays stale. Using the full Hashable value gives
                        // every change a unique identity.
                        ForEach(group.items, id: \.self) { task in
                            TaskListRow(
                                task: task,
                                isSelected: activePaths.contains(task.absolutePath),
                                onOpen: { onSelectFile($0.absolutePath) },
                                onChangeStatus: { task, newStatus in
                                    writeStatus(task: task, newStatus: newStatus)
                                },
                                onChangePriority: { task, newPriority in
                                    writePriority(task: task, newPriority: newPriority)
                                },
                                onChangeDue: { task, newDate in
                                    writeDue(task: task, newDate: newDate)
                                }
                            )
                        }
                    }
                }
            }
            .padding(.bottom, 12)
        }
    }

    // MARK: - Frontmatter writeback (Phase 7)

    private func writeStatus(task: TaskItem, newStatus: BrainTaskStatus) {
        // Optimistic: snap the in-memory model immediately so the row icon
        // updates without waiting for the file-system round-trip. Watcher
        // reparse later reconciles (same value → no visible jump).
        store.replace(task.with(status: .some(newStatus), unrecognizedStatusRaw: .some(nil)))
        // status 변경은 brain convention 에 따라 status/updated/completed/
        // waiting_on + body Timeline 까지 한 묶음으로 처리. 다른 필드(priority/
        // due) 는 기존 단일-키 writeback 경로 유지.
        // oldStatusRaw 는 unrecognizedStatusRaw 를 먼저 보고(legacy raw 보존),
        // 없을 때만 status enum 의 rawValue 로 fall back — Timeline 에 'doing'
        // 같은 legacy 값도 살아남도록.
        BrainStatusMutator.applyStatusChange(
            at: task.absolutePath,
            kind: .task,
            oldStatusRaw: task.unrecognizedStatusRaw ?? task.status?.rawValue,
            newStatusRaw: newStatus.rawValue
        )
        // File watcher in TaskFileListStore picks the change up and reparses.
    }

    private func writePriority(task: TaskItem, newPriority: BrainPriority?) {
        store.replace(task.with(priority: .some(newPriority)))
        BrainStatusMutator.applyPropertyChange(
            at: task.absolutePath,
            field: "priority",
            oldValue: task.priority?.rawValue,
            newValue: newPriority?.rawValue
        )
    }

    private func writeDue(task: TaskItem, newDate: Date?) {
        store.replace(task.with(dueDate: .some(newDate)))
        let oldSerialized = task.dueDate.map { BrainDateOnlyCodec.storageString(fromPickerDate: $0) }
        let newSerialized = newDate.map { BrainDateOnlyCodec.storageString(fromPickerDate: $0) }
        BrainStatusMutator.applyPropertyChange(
            at: task.absolutePath,
            field: "due",
            oldValue: oldSerialized,
            newValue: newSerialized
        )
    }
}
