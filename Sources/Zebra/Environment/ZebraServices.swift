import SwiftUI

/// Container for Zebra-only app-wide stores.
///
/// Why this exists: cmux is upstream, Zebra is a fork. We want upstream files
/// (AppDelegate, ContentView, tests) to mention Zebra in as few places as
/// possible so `git rebase upstream/main` stays cheap.
///
/// This is NOT an `ObservableObject` on purpose. Wrapping all 7 stores into a
/// single Observable would re-invalidate every consumer whenever any one of
/// them changes (or, if the wrapper does not forward `objectWillChange`,
/// `onChange(of: store.foo)` stops firing). Keep each store as its own
/// `ObservableObject`; the container just gives them a shared identity for
/// dependency injection.
///
/// See `/Users/han/.claude/plans/cmux-zbrown-cmux-wise-treasure.md` Phase 1.1
/// for the rationale and rollout plan.
@MainActor
struct ZebraServices {
    let sidebarMode: VerticalTabsSidebarModeState
    let vault: VerticalTabsSidebarVaultState
    let markdownFiles: MarkdownFileListStore
    let goals: GoalFileListStore
    let tasks: TaskFileListStore
    let people: PersonFileListStore
    let goalsViewState: GoalsViewState

    /// Build a fresh container with default-initialized stores. Call this once
    /// per main window in `AppDelegate.createMainWindow(...)`.
    static func makeDefault() -> ZebraServices {
        ZebraServices(
            sidebarMode: VerticalTabsSidebarModeState(),
            vault: VerticalTabsSidebarVaultState(),
            markdownFiles: MarkdownFileListStore(),
            goals: GoalFileListStore(),
            tasks: TaskFileListStore(),
            people: PersonFileListStore(),
            goalsViewState: GoalsViewState()
        )
    }

    /// Inject every Zebra store into the view's environment in one call.
    ///
    /// Each store is still exposed as its own `@EnvironmentObject` so existing
    /// Zebra views don't need to change. `@Environment(\.zebra)` also returns
    /// the container for cases where a view needs to read multiple stores
    /// without subscribing to any of them.
    func injectIntoEnvironment<V: View>(_ view: V) -> some View {
        view
            .environment(\.zebra, self)
            .environmentObject(sidebarMode)
            .environmentObject(vault)
            .environmentObject(markdownFiles)
            .environmentObject(goals)
            .environmentObject(tasks)
            .environmentObject(people)
            .environmentObject(goalsViewState)
    }
}

private struct ZebraServicesKey: EnvironmentKey {
    static let defaultValue: ZebraServices? = nil
}

extension EnvironmentValues {
    /// Optional Zebra service container. Returns `nil` when cmux is running
    /// without Zebra wiring (e.g., upstream-only test targets), which is the
    /// safety net the adapter pattern relies on.
    var zebra: ZebraServices? {
        get { self[ZebraServicesKey.self] }
        set { self[ZebraServicesKey.self] = newValue }
    }
}
