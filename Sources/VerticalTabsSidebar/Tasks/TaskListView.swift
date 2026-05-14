import SwiftUI

struct TaskListView: View {
    @ObservedObject var store: TaskFileListStore
    let activePaths: Set<String>
    let onSelectFile: (String) -> Void
    @StateObject private var viewModel = TaskListViewModel()
    @State private var filterStep: TaskFilterPopoverStep?

    var body: some View {
        // Read store.tasks directly in body so SwiftUI's ObservedObject
        // tracking definitively captures the subscription. Reading inside
        // a computed property was unreliable in this context — file-watcher
        // reassignments invalidated the view, but in-place mutations from
        // `replace()` did not.
        let tasksSnapshot = store.tasks
        return VStack(spacing: 0) {
            // Reserve the first-row slot so the toolbar lines up below the
            // titlebar buttons, matching the Goals/Documents modes.
            Color.clear.frame(height: SidebarWorkspaceListMetrics.firstRowTopOffset)
            TaskListToolbar(
                groupBy: viewModel.groupBy,
                existingFilterFields: Set(viewModel.filters.map(\.field)),
                availableOwners: availableOwners,
                filterStep: $filterStep,
                currentFilter: { field in
                    viewModel.filters.first(where: { $0.field == field })
                        ?? TaskFilter(field: field, op: .is, values: [])
                },
                onPickGroupBy: { viewModel.groupBy = $0 },
                onPickField: { field in
                    if !viewModel.filters.contains(where: { $0.field == field }) {
                        viewModel.filters.append(TaskFilter(field: field, op: .is, values: []))
                    }
                },
                onChangeFilterValues: { updated in
                    viewModel.setFilter(updated)
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
            if !viewModel.filters.isEmpty {
                chipRow
            }
            listContent(tasks: tasksSnapshot)
        }
        .background(BVColor.bg)
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(viewModel.filters) { f in
                    TaskFilterChipView(
                        filter: f,
                        onEdit: { filterStep = .value(f.field) },
                        onRemove: { viewModel.removeFilter(field: f.field) }
                    )
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
        }
        .background(BVColor.bg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(BVColor.border).frame(height: 1)
        }
    }

    private func listScrollView(tasks: [TaskItem]) -> some View {
        let filtered = TaskListViewModel.applyFilters(tasks, viewModel.filters)
        let groups = TaskListViewModel.groupTasks(filtered, by: viewModel.groupBy)
        return ScrollView {
            LazyVStack(spacing: 0, pinnedViews: []) {
                ForEach(groups) { group in
                    TaskGroupHeader(
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
        applyFrontmatter(task: task, key: "status", value: newStatus.rawValue)
    }

    private func writePriority(task: TaskItem, newPriority: BrainPriority?) {
        store.replace(task.with(priority: .some(newPriority)))
        applyFrontmatter(task: task, key: "priority", value: newPriority?.rawValue)
    }

    private func writeDue(task: TaskItem, newDate: Date?) {
        store.replace(task.with(dueDate: .some(newDate)))
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(identifier: "UTC")
        applyFrontmatter(task: task, key: "due", value: newDate.map { df.string(from: $0) })
    }

    private func applyFrontmatter(task: TaskItem, key: String, value: String?) {
        let url = URL(fileURLWithPath: task.absolutePath)
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else { return }
        let updated = BrainFrontmatterWriter.setScalar(key, to: value, in: content)
        guard updated != content,
              let newData = updated.data(using: .utf8) else { return }
        try? newData.write(to: url, options: .atomic)
        // File watcher in TaskFileListStore picks the change up and reparses.
    }
}
