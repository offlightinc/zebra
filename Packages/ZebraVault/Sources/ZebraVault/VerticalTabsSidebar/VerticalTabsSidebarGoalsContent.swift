import SwiftUI

public struct VerticalTabsSidebarGoalsContent: View {
    @ObservedObject public var state: VerticalTabsSidebarModeState
    @ObservedObject public var goalsStore: GoalFileListStore
    @ObservedObject public var viewState: GoalsViewState
    public let onSelectFile: (String) -> Void

    public init(
        state: VerticalTabsSidebarModeState,
        goalsStore: GoalFileListStore,
        viewState: GoalsViewState,
        onSelectFile: @escaping (String) -> Void
    ) {
        self.state = state
        self.goalsStore = goalsStore
        self.viewState = viewState
        self.onSelectFile = onSelectFile
    }

    public var body: some View {
        GoalsListView(
            store: goalsStore,
            modeState: state,
            viewState: viewState,
            onSelectFile: onSelectFile
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1)
        }
        .accessibilityIdentifier("VerticalTabsSidebarGoalsContent")
    }
}
