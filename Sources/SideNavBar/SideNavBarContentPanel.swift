import SwiftUI

struct SideNavBarContentPanel: View {
    static let expandedWidth: CGFloat = 240

    @ObservedObject var state: SideNavBarState
    @ObservedObject var store: MarkdownFileListStore
    let onSelectFile: (String) -> Void

    var body: some View {
        Group {
            if state.listVisible {
                SideNavBarMarkdownListView(
                    store: store,
                    state: state,
                    onSelectFile: onSelectFile
                )
                .frame(width: Self.expandedWidth)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 1)
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
                .accessibilityIdentifier("SideNavBarContentPanel")
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(.easeOut(duration: 0.15), value: state.listVisible)
    }
}
