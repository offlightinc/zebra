import SwiftUI

struct SideNavBarIconColumn: View {
    static let fixedWidth: CGFloat = 48
    static let topInset: CGFloat = SidebarWorkspaceListMetrics.firstRowTopOffset

    @ObservedObject var state: SideNavBarState

    var body: some View {
        VStack(spacing: 4) {
            ForEach(SideNavBarMode.allCases) { mode in
                iconButton(for: mode)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, Self.topInset)
        .padding(.bottom, 6)
        .frame(width: Self.fixedWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1)
        }
        .accessibilityIdentifier("SideNavBarIconColumn")
    }

    @ViewBuilder
    private func iconButton(for mode: SideNavBarMode) -> some View {
        let isSelected = state.selectedMode == mode
        Button {
            state.selectedMode = mode
        } label: {
            Image(systemName: mode.symbolName)
                .font(.system(size: 16, weight: .regular))
                .frame(width: 36, height: 36)
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color.secondary.opacity(0.18) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.label)
        .accessibilityIdentifier("SideNavBarIconColumn.button.\(mode.rawValue)")
    }
}
