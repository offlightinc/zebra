import SwiftUI

struct VerticalTabsSidebarGoalsContent: View {
    @ObservedObject var state: VerticalTabsSidebarModeState
    @ObservedObject var goalsStore: GoalFileListStore
    @ObservedObject var viewState: GoalsViewState
    let onSelectFile: (String) -> Void

    var body: some View {
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
