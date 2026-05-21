import SwiftUI

struct VerticalTabsSidebarMarkdownListView: View {
    @ObservedObject var store: MarkdownFileListStore
    @ObservedObject var state: VerticalTabsSidebarModeState
    let onSelectFile: (String) -> Void

    @State private var collapsedFolders: Set<String> = []
    @State private var persistenceRootPath: String?

    var body: some View {
        let entries = store.mdFiles
        let activePaths = state.activeMarkdownFilePaths
        let isScanning = store.isScanning
        let hasRoot = store.rootPath != nil

        Group {
            if !hasRoot {
                placeholderState(
                    text: String(localized: "verticalTabsSidebar.list.noWorkspace", defaultValue: "No workspace selected")
                )
            } else if entries.isEmpty && isScanning {
                loadingState
            } else if entries.isEmpty {
                placeholderState(
                    text: String(localized: "verticalTabsSidebar.list.empty", defaultValue: "No markdown files in this workspace")
                )
            } else {
                let root = MarkdownTreeFolder.build(from: entries)
                VStack(spacing: 0) {
                    toolbar(root: root)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(root.subfolders) { folder in
                                MarkdownFolderSubtreeView(
                                    folder: folder,
                                    depth: 0,
                                    activePaths: activePaths,
                                    collapsedFolders: collapsedFoldersBinding,
                                    onSelectFile: onSelectFile
                                )
                            }
                            ForEach(root.files) { entry in
                                MarkdownFileRow(
                                    displayName: entry.displayName,
                                    depth: 0,
                                    isSelected: activePaths.contains(entry.absolutePath),
                                    onTap: { [path = entry.absolutePath] in
                                        onSelectFile(path)
                                    }
                                )
                                .equatable()
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .accessibilityIdentifier("VerticalTabsSidebarMarkdownList.scroll")
                }
            }
        }
        .onAppear {
            bindPersistence(rootPath: store.rootPath)
        }
        .onChange(of: store.rootPath) { newRootPath in
            bindPersistence(rootPath: newRootPath)
        }
    }

    private func toolbar(root: MarkdownTreeFolder) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Button {
                collapseAll(root: root)
            } label: {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .safeHelp(
                String(localized: "verticalTabsSidebar.list.collapseAll.tooltip", defaultValue: "Collapse all folders")
            )
            .accessibilityLabel(
                String(localized: "verticalTabsSidebar.list.collapseAll.accessibilityLabel", defaultValue: "Collapse all")
            )
            .accessibilityIdentifier("VerticalTabsSidebarMarkdownList.collapseAll")
        }
        .padding(.horizontal, 6)
        .frame(height: ZebraSidebarMetrics.firstRowTopOffset)
    }

    private func collapseAll(root: MarkdownTreeFolder) {
        var paths: Set<String> = []
        collectFolderPaths(folder: root, into: &paths)
        setCollapsedFolders(paths)
    }

    private func collectFolderPaths(folder: MarkdownTreeFolder, into set: inout Set<String>) {
        if !folder.folderPath.isEmpty {
            set.insert(folder.folderPath)
        }
        for sub in folder.subfolders {
            collectFolderPaths(folder: sub, into: &set)
        }
    }

    private var collapsedFoldersBinding: Binding<Set<String>> {
        Binding(
            get: { collapsedFolders },
            set: { setCollapsedFolders($0) }
        )
    }

    private func bindPersistence(rootPath: String?) {
        guard rootPath != persistenceRootPath else { return }
        persistenceRootPath = rootPath
        let restored = VerticalTabsSidebarViewStatePersistence.loadDocumentState(rootPath: rootPath)
        collapsedFolders = Set(restored.collapsedFolders)
    }

    private func setCollapsedFolders(_ next: Set<String>) {
        collapsedFolders = next
        VerticalTabsSidebarViewStatePersistence.saveDocumentState(
            VerticalTabsSidebarViewStatePersistence.DocumentState(collapsedFolders: next.sorted()),
            rootPath: persistenceRootPath
        )
    }

    private var loadingState: some View {
        VStack {
            Spacer()
            ProgressView()
                .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func placeholderState(text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MarkdownFolderSubtreeView: View {
    let folder: MarkdownTreeFolder
    let depth: Int
    let activePaths: Set<String>
    @Binding var collapsedFolders: Set<String>
    let onSelectFile: (String) -> Void

    var body: some View {
        let expanded = !collapsedFolders.contains(folder.folderPath)
        MarkdownFolderRow(
            displayName: folder.displayName,
            depth: depth,
            expanded: expanded,
            onTap: { toggleCollapse(folderPath: folder.folderPath) }
        )
        if expanded {
            ForEach(folder.subfolders) { sub in
                MarkdownFolderSubtreeView(
                    folder: sub,
                    depth: depth + 1,
                    activePaths: activePaths,
                    collapsedFolders: $collapsedFolders,
                    onSelectFile: onSelectFile
                )
            }
            ForEach(folder.files) { entry in
                MarkdownFileRow(
                    displayName: entry.displayName,
                    depth: depth + 1,
                    isSelected: activePaths.contains(entry.absolutePath),
                    onTap: { [path = entry.absolutePath] in
                        onSelectFile(path)
                    }
                )
                .equatable()
            }
        }
    }

    private func toggleCollapse(folderPath: String) {
        if collapsedFolders.contains(folderPath) {
            collapsedFolders.remove(folderPath)
        } else {
            collapsedFolders.insert(folderPath)
        }
    }
}

private struct MarkdownFolderRow: View, Equatable {
    let displayName: String
    let depth: Int
    let expanded: Bool
    let onTap: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.displayName == rhs.displayName
            && lhs.depth == rhs.depth
            && lhs.expanded == rhs.expanded
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 10)
                Text(displayName)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, 12 + CGFloat(depth) * 14)
            .padding(.trailing, 12)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("VerticalTabsSidebarMarkdownList.folder")
    }
}

private struct MarkdownFileRow: View, Equatable {
    let displayName: String
    let depth: Int
    let isSelected: Bool
    let onTap: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.displayName == rhs.displayName
            && lhs.depth == rhs.depth
            && lhs.isSelected == rhs.isSelected
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                Text(displayName)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, 12 + 14 + CGFloat(depth) * 14)
            .padding(.trailing, 12)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
                    .padding(.horizontal, 6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("VerticalTabsSidebarMarkdownList.row")
    }
}

#if DEBUG
private func previewSampleEntries() -> [MarkdownFileEntry] {
    [
        MarkdownFileEntry(
            absolutePath: "/preview/workspace/README.md",
            displayName: "README.md",
            relativeParentPath: ""
        ),
        MarkdownFileEntry(
            absolutePath: "/preview/workspace/CLAUDE.md",
            displayName: "CLAUDE.md",
            relativeParentPath: ""
        ),
        MarkdownFileEntry(
            absolutePath: "/preview/workspace/docs/getting-started.md",
            displayName: "getting-started.md",
            relativeParentPath: "docs/"
        ),
        MarkdownFileEntry(
            absolutePath: "/preview/workspace/docs/ghostty-fork.md",
            displayName: "ghostty-fork.md",
            relativeParentPath: "docs/"
        ),
        MarkdownFileEntry(
            absolutePath: "/preview/workspace/docs/api/overview.md",
            displayName: "overview.md",
            relativeParentPath: "docs/api/"
        ),
        MarkdownFileEntry(
            absolutePath: "/preview/workspace/docs/api/auth.md",
            displayName: "auth.md",
            relativeParentPath: "docs/api/"
        ),
    ]
}

#Preview("Populated tree, one active") {
    VerticalTabsSidebarMarkdownListView(
        store: MarkdownFileListStore.previewStore(entries: previewSampleEntries()),
        state: VerticalTabsSidebarModeState(
            activeMarkdownFilePaths: ["/preview/workspace/docs/api/overview.md"],
            suppressPersistence: true
        ),
        onSelectFile: { _ in }
    )
    .frame(width: 260, height: 480)
    .background(Color(NSColor.windowBackgroundColor))
}

#Preview("Multiple active highlights") {
    VerticalTabsSidebarMarkdownListView(
        store: MarkdownFileListStore.previewStore(entries: previewSampleEntries()),
        state: VerticalTabsSidebarModeState(
            activeMarkdownFilePaths: [
                "/preview/workspace/README.md",
                "/preview/workspace/docs/getting-started.md",
                "/preview/workspace/docs/api/auth.md",
            ],
            suppressPersistence: true
        ),
        onSelectFile: { _ in }
    )
    .frame(width: 260, height: 480)
    .background(Color(NSColor.windowBackgroundColor))
}

#Preview("Empty workspace") {
    VerticalTabsSidebarMarkdownListView(
        store: MarkdownFileListStore.previewStore(entries: []),
        state: VerticalTabsSidebarModeState(suppressPersistence: true),
        onSelectFile: { _ in }
    )
    .frame(width: 260, height: 480)
    .background(Color(NSColor.windowBackgroundColor))
}

#Preview("No workspace selected") {
    VerticalTabsSidebarMarkdownListView(
        store: MarkdownFileListStore.previewStore(entries: [], rootPath: nil),
        state: VerticalTabsSidebarModeState(suppressPersistence: true),
        onSelectFile: { _ in }
    )
    .frame(width: 260, height: 480)
    .background(Color(NSColor.windowBackgroundColor))
}

#Preview("Scanning") {
    VerticalTabsSidebarMarkdownListView(
        store: MarkdownFileListStore.previewStore(entries: [], isScanning: true),
        state: VerticalTabsSidebarModeState(suppressPersistence: true),
        onSelectFile: { _ in }
    )
    .frame(width: 260, height: 480)
    .background(Color(NSColor.windowBackgroundColor))
}

#Preview("Dark — populated") {
    VerticalTabsSidebarMarkdownListView(
        store: MarkdownFileListStore.previewStore(entries: previewSampleEntries()),
        state: VerticalTabsSidebarModeState(
            activeMarkdownFilePaths: ["/preview/workspace/CLAUDE.md"],
            suppressPersistence: true
        ),
        onSelectFile: { _ in }
    )
    .frame(width: 260, height: 480)
    .background(Color(NSColor.windowBackgroundColor))
    .preferredColorScheme(.dark)
}
#endif
