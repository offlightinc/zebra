import SwiftUI

public struct MarkdownChatPillOverlay: View {
    public static let contentBottomInset: CGFloat = MarkdownChatPillLayout.baseContentBottomInset

    private static let horizontalInset: CGFloat = 24
    private static let bottomInset: CGFloat = MarkdownChatPillLayout.floatingBottomPadding
    private static let motion = Animation.timingCurve(0.4, 0.0, 0.2, 1.0, duration: 0.30)

    @Binding private var isExpanded: Bool
    private let displayTitle: String
    private let availableContentHeight: CGFloat?
    private let activeAgent: MarkdownPillAgent?
    private let onSubmit: (_ text: String, _ agent: MarkdownPillAgent, _ executablePath: String) -> Void
    private let onManageDefaultAgent: ((_ agent: ZebraAgentKind?, _ installApproved: Bool) -> Void)?
    private let onHeightChange: ((CGFloat) -> Void)?

    public init(
        isExpanded: Binding<Bool>,
        displayTitle: String,
        availableContentHeight: CGFloat? = nil,
        activeAgent: MarkdownPillAgent?,
        onSubmit: @escaping (_ text: String, _ agent: MarkdownPillAgent, _ executablePath: String) -> Void,
        onManageDefaultAgent: ((_ agent: ZebraAgentKind?, _ installApproved: Bool) -> Void)? = nil,
        onHeightChange: ((CGFloat) -> Void)? = nil
    ) {
        self._isExpanded = isExpanded
        self.displayTitle = displayTitle
        self.availableContentHeight = availableContentHeight
        self.activeAgent = activeAgent
        self.onSubmit = onSubmit
        self.onManageDefaultAgent = onManageDefaultAgent
        self.onHeightChange = onHeightChange
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            if isExpanded {
                Rectangle()
                    .fill(Color.black.opacity(0.001))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(Self.motion) {
                            isExpanded = false
                        }
                    }
            }

            MarkdownChatPill(
                isExpanded: $isExpanded,
                displayTitle: displayTitle,
                availableContentHeight: availableContentHeight,
                activeAgent: activeAgent,
                onSubmit: onSubmit,
                onManageDefaultAgent: onManageDefaultAgent,
                onHeightChange: onHeightChange
            )
            .padding(.horizontal, Self.horizontalInset)
            .padding(.bottom, Self.bottomInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}
