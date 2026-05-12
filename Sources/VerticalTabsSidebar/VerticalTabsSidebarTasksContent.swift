import SwiftUI

struct VerticalTabsSidebarTasksContent: View {
    @ObservedObject var state: VerticalTabsSidebarModeState
    @ObservedObject var store: MarkdownFileListStore
    let onSelectFile: (String) -> Void

    var body: some View {
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
        .accessibilityIdentifier("VerticalTabsSidebarTasksContent")
    }
}
