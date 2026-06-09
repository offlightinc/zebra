import SwiftUI
import ZebraVault

/// Zebra-side wiring that used to live inside cmux's `ContentView`:
/// `ActiveMarkdownPathsObserver` ownership, four "vault root → store"
/// bindings, and the `onChange` listeners that drive them.
///
/// Attach once at the cmux root with `.zebraStoreBindings()`. ContentView
/// stays free of Zebra store names; this modifier reads them all via its
/// own `@EnvironmentObject` declarations.
private struct ZebraStoreBindingsModifier: ViewModifier {
    @EnvironmentObject var tabManager: TabManager
    @EnvironmentObject var modeState: VerticalTabsSidebarModeState
    @EnvironmentObject var vaultState: VerticalTabsSidebarVaultState
    @EnvironmentObject var markdownFiles: MarkdownFileListStore
    @EnvironmentObject var goals: GoalFileListStore
    @EnvironmentObject var tasks: TaskFileListStore
    @EnvironmentObject var people: PersonFileListStore

    @StateObject private var activeMarkdownPathsObserver = ActiveMarkdownPathsObserver()

    func body(content: Content) -> some View {
        content
            .onAppear {
                activeMarkdownPathsObserver.wire(tabManager: tabManager)
                modeState.activeMarkdownFilePaths = activeMarkdownPathsObserver.paths
                syncVaultRootedStores()
            }
            .onChange(of: vaultState.selectedVaultPath) { _ in
                syncVaultRootedStores()
            }
            .onChange(of: vaultState.selectedVaultWasExplicitlyChosen) { _ in
                syncVaultRootedStores()
            }
            .onChange(of: activeMarkdownPathsObserver.paths) { newPaths in
                modeState.activeMarkdownFilePaths = newPaths
            }
    }

    private func syncVaultRootedStores() {
        let root = vaultState.selectedVaultWasExplicitlyChosen ? vaultState.selectedVault?.path : nil
        markdownFiles.bind(rootPath: root)
        goals.bind(vaultRoot: root)
        tasks.bind(vaultRoot: root)
        people.bind(vaultRoot: root)
    }
}

extension View {
    /// Attach Zebra's store-binding observers to a cmux view tree. Safe to
    /// call exactly once at the root — the modifier owns the underlying
    /// `ActiveMarkdownPathsObserver` as `@StateObject` so its lifetime is
    /// tied to the modifier's place in the tree.
    func zebraStoreBindings() -> some View {
        modifier(ZebraStoreBindingsModifier())
    }
}
