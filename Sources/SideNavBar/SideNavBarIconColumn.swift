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
        let isActiveAndVisible = isSelected && state.listVisible
        Button {
            state.handleIconClick(mode)
        } label: {
            Image(systemName: mode.symbolName)
                .font(.system(size: 16, weight: .regular))
                .frame(width: 36, height: 36)
                .foregroundColor(isActiveAndVisible ? .accentColor : (isSelected ? .primary : .secondary))
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isActiveAndVisible ? Color.secondary.opacity(0.22) : (isSelected ? Color.secondary.opacity(0.10) : Color.clear))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode.label)
        .accessibilityIdentifier("SideNavBarIconColumn.button.\(mode.rawValue)")
    }
}
