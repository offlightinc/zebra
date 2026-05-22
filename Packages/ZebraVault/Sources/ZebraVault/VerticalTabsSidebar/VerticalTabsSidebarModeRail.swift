import SwiftUI

public struct VerticalTabsSidebarModeRail: View {
    public static let fixedWidth: CGFloat = 48
    public static let topInset: CGFloat = ZebraSidebarMetrics.firstRowTopOffset

    @ObservedObject public var state: VerticalTabsSidebarModeState
    private let footer: AnyView?

    public init(state: VerticalTabsSidebarModeState, footer: AnyView? = nil) {
        self.state = state
        self.footer = footer
    }

    public var body: some View {
        VStack(spacing: 4) {
            ForEach(VerticalTabsSidebarMode.allCases) { mode in
                iconButton(for: mode)
            }
            Spacer(minLength: 0)
            // Footer slot — `?` / `⚙` 같은 글로벌 액션 (이전엔 sidebar footer 에
            // 있었음). 디자인 spec (`/Users/han/zebra_design/zebra_sync/`) SECTION 1
            // layout change. ZebraVault 안의 ModeRail 은 view type 만 제공, 실제
            // help / settings button 은 cmux app module 의 ZebraSidebarBody 가
            // AnyView 로 wrapping 해 넘김 (cmux app module 안의 internal struct
            // 라 ZebraVault 가 직접 type 명시 불가능).
            if let footer {
                footer
            }
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
        .accessibilityIdentifier("VerticalTabsSidebarModeRail")
    }

    @ViewBuilder
    private func iconButton(for mode: VerticalTabsSidebarMode) -> some View {
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
        .accessibilityIdentifier("VerticalTabsSidebarModeRail.button.\(mode.rawValue)")
    }
}

#if DEBUG
#Preview("Terminal selected, list visible") {
    VerticalTabsSidebarModeRail(
        state: VerticalTabsSidebarModeState(
            selectedMode: .terminal,
            listVisible: true,
            suppressPersistence: true
        )
    )
    .frame(height: 480)
    .background(Color(NSColor.windowBackgroundColor))
}

#Preview("Goals selected, list hidden") {
    VerticalTabsSidebarModeRail(
        state: VerticalTabsSidebarModeState(
            selectedMode: .goals,
            listVisible: false,
            suppressPersistence: true
        )
    )
    .frame(height: 480)
    .background(Color(NSColor.windowBackgroundColor))
}

#Preview("Dark — documents selected") {
    VerticalTabsSidebarModeRail(
        state: VerticalTabsSidebarModeState(
            selectedMode: .documents,
            listVisible: true,
            suppressPersistence: true
        )
    )
    .frame(height: 480)
    .background(Color(NSColor.windowBackgroundColor))
    .preferredColorScheme(.dark)
}
#endif
