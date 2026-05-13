import SwiftUI

struct GoalsListSnapshot: Equatable {
    let entries: [GoalEntry]
    let activePaths: Set<String>
    let hasRoot: Bool
    let isScanning: Bool
    let picker: GoalsViewState.Picker
}

// Container: observes stores, computes immutable snapshot, hands a pure body view
// closures. Keeps ObservableObject references above the LazyVStack boundary so
// unrelated @Published changes never invalidate the list subtree.
// See CLAUDE.md "Snapshot boundary for list subtrees".
struct GoalsListView: View {
    @ObservedObject var store: GoalFileListStore
    @ObservedObject var modeState: VerticalTabsSidebarModeState
    @ObservedObject var viewState: GoalsViewState
    let onSelectFile: (String) -> Void

    var body: some View {
        GoalsListBody(
            snapshot: GoalsListSnapshot(
                entries: store.goals,
                activePaths: modeState.activeMarkdownFilePaths,
                hasRoot: store.rootPath != nil,
                isScanning: store.isScanning,
                picker: viewState.picker
            ),
            onSelectFile: onSelectFile,
            onPickerSelect: { [weak viewState] picker in
                viewState?.picker = picker
            }
        )
    }
}

// Pure list subtree: receives an immutable snapshot plus closures. Holds no
// ObservableObject references, so changes outside the snapshot cannot ripple
// into LazyVStack invalidation.
private struct GoalsListBody: View {
    let snapshot: GoalsListSnapshot
    let onSelectFile: (String) -> Void
    let onPickerSelect: (GoalsViewState.Picker) -> Void

    @State private var collapsedOutlineIds: Set<String> = []
    @State private var collapsedCadenceSections: Set<GoalCadence> = []
    @State private var collapsedStatusSections: Set<GoalStatus> = []

    var body: some View {
        // Collapse-all sits as the first row at the very top of the sidebar
        // column so it lines up horizontally with the titlebar's bell/+ buttons,
        // matching the placement used by VerticalTabsSidebarMarkdownListView's
        // toolbar in the documents/tasks modes. Picker drops into the second row.
        // Reserve the first-row slot even when entries are empty so the column's
        // top edge does not jump when the goals list populates.
        VStack(spacing: 0) {
            collapseAllToolbar
            GoalsPicker(selection: snapshot.picker, onSelect: onPickerSelect)
                .padding(.horizontal, GoalsDesignTokens.pickerOuterHorizontalPadding)
                .padding(.vertical, GoalsDesignTokens.pickerVerticalPadding)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var content: some View {
        if !snapshot.hasRoot {
            placeholder(
                String(localized: "verticalTabsSidebar.goals.empty.noVault", defaultValue: "No vault selected")
            )
        } else if snapshot.entries.isEmpty && snapshot.isScanning {
            VStack {
                Spacer()
                ProgressView().controlSize(.small)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if snapshot.entries.isEmpty {
            placeholder(
                String(localized: "verticalTabsSidebar.goals.empty.noGoals", defaultValue: "No goals in vault")
            )
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    layoutBody
                }
                .padding(.bottom, 6)
            }
            .id(snapshot.picker)
            .accessibilityIdentifier("VerticalTabsSidebar.Goals.scroll")
        }
    }

    // Same icon/hit area/font as VerticalTabsSidebarMarkdownListView so docs and
    // goals modes share visual rhythm with the titlebar trailing buttons.
    // Button only enables when there is something to collapse.
    private var collapseAllToolbar: some View {
        let canCollapse = snapshot.hasRoot && !snapshot.entries.isEmpty
        return HStack(spacing: 0) {
            Spacer(minLength: 0)
            Button {
                collapseAll()
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
                String(localized: "verticalTabsSidebar.goals.collapseAll.tooltip", defaultValue: "Collapse all")
            )
            .accessibilityLabel(
                String(localized: "verticalTabsSidebar.goals.collapseAll.accessibilityLabel", defaultValue: "Collapse all")
            )
            .accessibilityIdentifier("VerticalTabsSidebar.Goals.collapseAll")
        }
        .padding(.horizontal, 6)
        .frame(height: SidebarWorkspaceListMetrics.firstRowTopOffset)
    }

    private func collapseAll() {
        switch snapshot.picker {
        case .outline:
            var ids: Set<String> = []
            let tree = GoalOutlineTree.build(entries: snapshot.entries)
            collectAllOutlineIds(nodes: tree.roots, into: &ids)
            collapsedOutlineIds = ids
        case .cadence:
            collapsedCadenceSections = Set(GoalCadence.allCases)
        case .status:
            collapsedStatusSections = Set(GoalStatus.allCases)
        }
    }

    private func collectAllOutlineIds(nodes: [GoalOutlineNode], into ids: inout Set<String>) {
        for node in nodes {
            ids.insert(node.entry.goalId)
            collectAllOutlineIds(nodes: node.children, into: &ids)
        }
    }

    // `.equatable()` lets SwiftUI skip body re-eval (and the build/bucketize work
    // inside each layout) when the value inputs are unchanged. Mirrors cmux's
    // existing per-row Equatable shim pattern (see TabItemView in ContentView.swift
    // and the rows in SessionIndexView.swift). Closures and Bindings stay
    // capture-by-reference and are excluded from equality on purpose — they only
    // fire actions, never participate in identity.
    @ViewBuilder
    private var layoutBody: some View {
        switch snapshot.picker {
        case .outline:
            OutlineLayout(
                entries: snapshot.entries,
                activePaths: snapshot.activePaths,
                collapsedIds: $collapsedOutlineIds,
                onSelectFile: onSelectFile
            )
            .equatable()
        case .cadence:
            CadenceLayout(
                entries: snapshot.entries,
                activePaths: snapshot.activePaths,
                collapsedSections: $collapsedCadenceSections,
                onSelectFile: onSelectFile
            )
            .equatable()
        case .status:
            StatusLayout(
                entries: snapshot.entries,
                activePaths: snapshot.activePaths,
                collapsedSections: $collapsedStatusSections,
                onSelectFile: onSelectFile
            )
            .equatable()
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
}

// MARK: - Picker

private struct GoalsPicker: View {
    let selection: GoalsViewState.Picker
    let onSelect: (GoalsViewState.Picker) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(GoalsViewState.Picker.allCases, id: \.self) { option in
                segment(for: option)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: GoalsDesignTokens.pickerCornerRadius, style: .continuous)
                .fill(Color(nsColor: .tertiarySystemFill))
        )
        .frame(height: GoalsDesignTokens.pickerHeight)
    }

    @ViewBuilder
    private func segment(for option: GoalsViewState.Picker) -> some View {
        let isSelected = selection == option
        Button {
            if selection != option {
                onSelect(option)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: option.symbolName)
                    .font(.system(size: 10, weight: .regular))
                Text(option.title)
                    .font(.system(size: GoalsDesignTokens.pickerFontSize, weight: .semibold))
            }
            .foregroundStyle(isSelected ? Color(nsColor: .labelColor) : Color(nsColor: .secondaryLabelColor))
            .frame(maxWidth: .infinity)
            .frame(height: GoalsDesignTokens.pickerHeight - 4)
            .background(
                RoundedRectangle(cornerRadius: GoalsDesignTokens.pickerSegmentCornerRadius, style: .continuous)
                    .fill(isSelected ? Color(nsColor: .controlBackgroundColor) : Color.clear)
                    .shadow(color: isSelected ? Color.black.opacity(0.08) : .clear, radius: 1, y: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("VerticalTabsSidebar.Goals.picker.\(option.rawValue)")
    }
}

private extension GoalsViewState.Picker {
    var title: String {
        switch self {
        case .outline:
            return String(localized: "verticalTabsSidebar.goals.picker.outline", defaultValue: "Outline")
        case .cadence:
            return String(localized: "verticalTabsSidebar.goals.picker.cadence", defaultValue: "Cadence")
        case .status:
            return String(localized: "verticalTabsSidebar.goals.picker.status", defaultValue: "Status")
        }
    }

    var symbolName: String {
        switch self {
        case .outline: return "list.bullet.indent"
        case .cadence: return "calendar"
        case .status: return "circle.grid.2x2"
        }
    }
}

// MARK: - Outline

private struct OutlineLayout: View, Equatable {
    let entries: [GoalEntry]
    let activePaths: Set<String>
    @Binding var collapsedIds: Set<String>
    let onSelectFile: (String) -> Void

    // Compare only value inputs. onSelectFile captures may be stale and that is
    // fine — they fire actions, not identity. The Binding's wrappedValue
    // participates via `collapsedIds`.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.entries == rhs.entries
            && lhs.activePaths == rhs.activePaths
            && lhs.collapsedIds == rhs.collapsedIds
    }

    var body: some View {
        let tree = GoalOutlineTree.build(entries: entries)
        let visibleItems = flatten(tree: tree, collapsedIds: collapsedIds)
        GoalGroupHeader(
            title: String(localized: "verticalTabsSidebar.goals.outline.rootTitle", defaultValue: "Goals"),
            count: entries.count
        )
        ForEach(visibleItems, id: \.entry.id) { item in
            GoalOutlineRow(
                displayName: item.entry.displayName,
                depth: item.depth,
                hasChildren: item.hasChildren,
                expanded: item.expanded,
                isCompleted: item.entry.status == .completed,
                isSelected: activePaths.contains(item.entry.absolutePath),
                onChevronTap: {
                    toggle(id: item.entry.goalId)
                },
                onRowTap: { [path = item.entry.absolutePath] in
                    onSelectFile(path)
                }
            )
            .equatable()
        }
    }

    private func toggle(id: String) {
        if collapsedIds.contains(id) {
            collapsedIds.remove(id)
        } else {
            collapsedIds.insert(id)
        }
    }

    private func flatten(tree: GoalOutlineTreeResult, collapsedIds: Set<String>) -> [GoalOutlineVisibleItem] {
        var items: [GoalOutlineVisibleItem] = []
        func walk(_ nodes: [GoalOutlineNode], depth: Int) {
            for node in nodes {
                let hasChildren = !node.children.isEmpty
                let expanded = !collapsedIds.contains(node.entry.goalId)
                items.append(GoalOutlineVisibleItem(
                    entry: node.entry,
                    depth: depth,
                    hasChildren: hasChildren,
                    expanded: expanded
                ))
                if hasChildren && expanded {
                    walk(node.children, depth: depth + 1)
                }
            }
        }
        walk(tree.roots, depth: 0)
        return items
    }
}

struct GoalOutlineVisibleItem {
    let entry: GoalEntry
    let depth: Int
    let hasChildren: Bool
    let expanded: Bool
}

struct GoalOutlineNode {
    let entry: GoalEntry
    var children: [GoalOutlineNode]
}

struct GoalOutlineTreeResult {
    let roots: [GoalOutlineNode]
}

enum GoalOutlineTree {
    static func build(entries: [GoalEntry]) -> GoalOutlineTreeResult {
        let byId: [String: GoalEntry] = Dictionary(entries.map { ($0.goalId, $0) }, uniquingKeysWith: { a, _ in a })
        var childrenById: [String: [GoalEntry]] = [:]
        var roots: [GoalEntry] = []
        for entry in entries {
            if let parentId = entry.parentGoalId, byId[parentId] != nil {
                childrenById[parentId, default: []].append(entry)
            } else {
                roots.append(entry)
            }
        }
        func makeNode(_ entry: GoalEntry) -> GoalOutlineNode {
            let kids = (childrenById[entry.goalId] ?? []).map { makeNode($0) }
            return GoalOutlineNode(entry: entry, children: kids)
        }
        return GoalOutlineTreeResult(roots: roots.map { makeNode($0) })
    }
}

// MARK: - Cadence

private struct CadenceLayout: View, Equatable {
    let entries: [GoalEntry]
    let activePaths: Set<String>
    @Binding var collapsedSections: Set<GoalCadence>
    let onSelectFile: (String) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.entries == rhs.entries
            && lhs.activePaths == rhs.activePaths
            && lhs.collapsedSections == rhs.collapsedSections
    }

    var body: some View {
        let buckets = bucketize(entries: entries)
        ForEach(GoalCadence.allCases, id: \.self) { cadence in
            let bucket = buckets[cadence] ?? []
            let isExpanded = !collapsedSections.contains(cadence)
            GoalCollapsibleHeader(
                title: cadence.label,
                count: bucket.count,
                isExpanded: isExpanded,
                onToggle: { toggle(cadence) }
            )
            .equatable()
            if isExpanded {
                ForEach(bucket, id: \.id) { entry in
                    GoalCadenceRow(
                        displayName: entry.displayName,
                        due: GoalDueLabelBuilder.descriptor(for: entry.targetDate),
                        isCompleted: entry.status == .completed,
                        isSelected: activePaths.contains(entry.absolutePath),
                        onTap: { [path = entry.absolutePath] in
                            onSelectFile(path)
                        }
                    )
                    .equatable()
                }
            }
        }
    }

    private func toggle(_ cadence: GoalCadence) {
        if collapsedSections.contains(cadence) {
            collapsedSections.remove(cadence)
        } else {
            collapsedSections.insert(cadence)
        }
    }

    private func bucketize(entries: [GoalEntry]) -> [GoalCadence: [GoalEntry]] {
        var dict: [GoalCadence: [GoalEntry]] = [:]
        for entry in entries {
            dict[entry.cadence, default: []].append(entry)
        }
        for key in dict.keys {
            dict[key]?.sort { lhs, rhs in
                switch (lhs.targetDate, rhs.targetDate) {
                case let (l?, r?):
                    return l < r
                case (nil, _?):
                    return false
                case (_?, nil):
                    return true
                case (nil, nil):
                    return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
                }
            }
        }
        return dict
    }
}

// MARK: - Status

private struct StatusLayout: View, Equatable {
    let entries: [GoalEntry]
    let activePaths: Set<String>
    @Binding var collapsedSections: Set<GoalStatus>
    let onSelectFile: (String) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.entries == rhs.entries
            && lhs.activePaths == rhs.activePaths
            && lhs.collapsedSections == rhs.collapsedSections
    }

    var body: some View {
        let buckets = bucketize(entries: entries)
        ForEach(GoalStatus.allCases, id: \.self) { status in
            let bucket = buckets[status] ?? []
            let isExpanded = !collapsedSections.contains(status)
            GoalCollapsibleHeader(
                title: status.label,
                count: bucket.count,
                isExpanded: isExpanded,
                onToggle: { toggle(status) }
            )
            .equatable()
            if isExpanded {
                ForEach(bucket, id: \.id) { entry in
                    GoalStatusRow(
                        displayName: entry.displayName,
                        milestoneDone: entry.milestoneDone,
                        milestoneTotal: entry.milestoneTotal,
                        isCompleted: entry.status == .completed,
                        isSelected: activePaths.contains(entry.absolutePath),
                        onTap: { [path = entry.absolutePath] in
                            onSelectFile(path)
                        }
                    )
                    .equatable()
                }
            }
        }
    }

    private func toggle(_ status: GoalStatus) {
        if collapsedSections.contains(status) {
            collapsedSections.remove(status)
        } else {
            collapsedSections.insert(status)
        }
    }

    private func bucketize(entries: [GoalEntry]) -> [GoalStatus: [GoalEntry]] {
        var dict: [GoalStatus: [GoalEntry]] = [:]
        for entry in entries {
            dict[entry.status, default: []].append(entry)
        }
        return dict
    }
}

#if DEBUG
private func sampleEntries() -> [GoalEntry] {
    let cal = Calendar(identifier: .gregorian)
    let now = Date()
    func dayOffset(_ days: Int) -> Date {
        cal.date(byAdding: .day, value: days, to: now)!
    }
    return [
        GoalEntry(absolutePath: "/p/g1.md", displayName: "Product revenue health diagnosis",
                  goalId: "G1", parentGoalId: nil,
                  status: .active, cadence: .weekly, targetDate: dayOffset(48),
                  milestoneDone: 4, milestoneTotal: 9),
        GoalEntry(absolutePath: "/p/g1-1.md", displayName: "Acquisition health",
                  goalId: "G1-1", parentGoalId: "G1",
                  status: .active, cadence: .weekly, targetDate: dayOffset(18),
                  milestoneDone: 2, milestoneTotal: 4),
        GoalEntry(absolutePath: "/p/g1-1-1.md", displayName: "Offlight Acquisition 진단",
                  goalId: "G1-1-1", parentGoalId: "G1-1",
                  status: .completed, cadence: .daily, targetDate: dayOffset(-5),
                  milestoneDone: 3, milestoneTotal: 3),
        GoalEntry(absolutePath: "/p/g1-1-2.md", displayName: "Signup cliff 가설 검증",
                  goalId: "G1-1-2", parentGoalId: "G1-1",
                  status: .active, cadence: .daily, targetDate: dayOffset(7),
                  milestoneDone: 1, milestoneTotal: 3),
        GoalEntry(absolutePath: "/p/g2.md", displayName: "Hire founding designer",
                  goalId: "G2", parentGoalId: nil,
                  status: .active, cadence: .weekly, targetDate: dayOffset(93),
                  milestoneDone: 2, milestoneTotal: 6),
        GoalEntry(absolutePath: "/p/g2-1.md", displayName: "포트폴리오 30 개 리뷰",
                  goalId: "G2-1", parentGoalId: "G2",
                  status: .active, cadence: .weekly, targetDate: dayOffset(63),
                  milestoneDone: 12, milestoneTotal: 30),
        GoalEntry(absolutePath: "/p/g3.md", displayName: "Daily writing habit",
                  goalId: "G3", parentGoalId: nil,
                  status: .active, cadence: .daily, targetDate: nil,
                  milestoneDone: 11, milestoneTotal: 14),
        GoalEntry(absolutePath: "/p/g4.md", displayName: "Q3 strategy memo",
                  goalId: "G4", parentGoalId: nil,
                  status: .draft, cadence: .quarterly, targetDate: dayOffset(140),
                  milestoneDone: 0, milestoneTotal: 5),
    ]
}

#Preview("Outline") {
    GoalsListView(
        store: GoalFileListStore.previewStore(entries: sampleEntries()),
        modeState: VerticalTabsSidebarModeState(
            activeMarkdownFilePaths: ["/p/g1-1-1.md"],
            suppressPersistence: true
        ),
        viewState: GoalsViewState(picker: .outline, suppressPersistence: true),
        onSelectFile: { _ in }
    )
    .frame(width: 240, height: 600)
    .background(Color(NSColor.windowBackgroundColor))
}

#Preview("Cadence") {
    GoalsListView(
        store: GoalFileListStore.previewStore(entries: sampleEntries()),
        modeState: VerticalTabsSidebarModeState(suppressPersistence: true),
        viewState: GoalsViewState(picker: .cadence, suppressPersistence: true),
        onSelectFile: { _ in }
    )
    .frame(width: 240, height: 600)
    .background(Color(NSColor.windowBackgroundColor))
}

#Preview("Status") {
    GoalsListView(
        store: GoalFileListStore.previewStore(entries: sampleEntries()),
        modeState: VerticalTabsSidebarModeState(suppressPersistence: true),
        viewState: GoalsViewState(picker: .status, suppressPersistence: true),
        onSelectFile: { _ in }
    )
    .frame(width: 240, height: 600)
    .background(Color(NSColor.windowBackgroundColor))
}

#Preview("Empty vault") {
    GoalsListView(
        store: GoalFileListStore.previewStore(entries: [], rootPath: "/preview/vault/goals"),
        modeState: VerticalTabsSidebarModeState(suppressPersistence: true),
        viewState: GoalsViewState(picker: .outline, suppressPersistence: true),
        onSelectFile: { _ in }
    )
    .frame(width: 240, height: 400)
    .background(Color(NSColor.windowBackgroundColor))
}
#endif
