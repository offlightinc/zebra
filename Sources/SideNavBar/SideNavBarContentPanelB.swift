import SwiftUI

struct SideNavBarContentPanelB: View {
    static let listWidth: CGFloat = 200
    static let detailWidth: CGFloat = 320
    static let totalWidth: CGFloat = listWidth + detailWidth

    @ObservedObject var state: SideNavBarState

    var body: some View {
        HStack(spacing: 0) {
            SideNavBarMarkdownListViewB(state: state)
                .frame(width: Self.listWidth)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 1)
                }
            SideNavBarMarkdownDetailViewB(state: state)
                .frame(width: Self.detailWidth)
        }
        .frame(width: Self.totalWidth)
        .frame(maxHeight: .infinity)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1)
        }
        .accessibilityIdentifier("SideNavBarContentPanelB")
    }
}
