import MarkdownUI
import SwiftUI

struct SideNavBarDetailColumnD: View {
    static let width: CGFloat = 320

    @ObservedObject var state: SideNavBarState

    var body: some View {
        VStack(spacing: 0) {
            if let path = state.selectedMarkdownFilePath,
               let entry = FakeMarkdownDataD.entry(for: path) {
                detailHeader(entry: entry)
                Divider()
                ScrollView {
                    Markdown(entry.content)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                emptyState
            }
        }
        .padding(.top, SidebarWorkspaceListMetrics.firstRowTopOffset)
        .frame(width: Self.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1)
        }
        .accessibilityIdentifier("SideNavBarDetailColumnD")
    }

    @ViewBuilder
    private func detailHeader(entry: FakeMarkdownEntryD) -> some View {
        HStack(spacing: 6) {
            Text(entry.displayName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary)
            if !entry.relativeParent.isEmpty {
                Text(entry.relativeParent)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack {
            Spacer()
            Text(String(localized: "sideNavBar.detail.empty", defaultValue: "Select a file from the list"))
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
