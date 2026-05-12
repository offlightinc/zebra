import SwiftUI

struct SideNavBarContentPanelC: View {
    static let width: CGFloat = 240

    let onOpenFilePreview: (String) -> Void

    @State private var selectedPath: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(FakeMarkdownDataC.entries) { entry in
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
        .accessibilityIdentifier("SideNavBarContentPanelC")
    }

    @ViewBuilder
    private func rowView(entry: FakeMarkdownEntryC) -> some View {
        let isSelected = selectedPath == entry.absolutePath
        Button {
            selectedPath = entry.absolutePath
            onOpenFilePreview(entry.absolutePath)
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
        .accessibilityIdentifier("SideNavBarContentPanelC.row.\(entry.absolutePath)")
    }
}
