import SwiftUI

public struct VerticalTabsSidebarDocumentsContent: View {
    @ObservedObject public var state: VerticalTabsSidebarModeState
    @ObservedObject public var store: MarkdownFileListStore
    public let onSelectFile: (String) -> Void

    public init(
        state: VerticalTabsSidebarModeState,
        store: MarkdownFileListStore,
        onSelectFile: @escaping (String) -> Void
    ) {
        self.state = state
        self.store = store
        self.onSelectFile = onSelectFile
    }

    public var body: some View {
        VerticalTabsSidebarMarkdownListView(
            store: store,
            state: state,
            onSelectFile: onSelectFile
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1)
        }
        .accessibilityIdentifier("VerticalTabsSidebarDocumentsContent")
    }
}
