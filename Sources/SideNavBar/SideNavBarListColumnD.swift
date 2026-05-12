import SwiftUI

struct SideNavBarListColumnD: View {
    static let width: CGFloat = 200

    @ObservedObject var state: SideNavBarState

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(FakeMarkdownDataD.entries) { entry in
                        rowView(entry: entry)
                    }
                }
                .padding(.vertical, 4)
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
        .accessibilityIdentifier("SideNavBarListColumnD")
    }

    @ViewBuilder
    private func rowView(entry: FakeMarkdownEntryD) -> some View {
        let isSelected = state.selectedMarkdownFilePath == entry.path
        Button {
            state.selectedMarkdownFilePath = entry.path
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.displayName)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                if !entry.relativeParent.isEmpty {
                    Text(entry.relativeParent)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
                    .padding(.horizontal, 6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("SideNavBarListColumnD.row.\(entry.path)")
    }
}
