import SwiftUI

public struct MarkdownChatPillOverlay: View {
    public static let contentBottomInset: CGFloat = 160

    private static let horizontalInset: CGFloat = 24
    private static let bottomInset: CGFloat = 22
    private static let motion = Animation.timingCurve(0.4, 0.0, 0.2, 1.0, duration: 0.30)

    @Binding private var isExpanded: Bool
    private let displayTitle: String
    private let activeAgent: MarkdownPillAgent?
    private let onSubmit: (_ text: String, _ agent: MarkdownPillAgent) -> Void

    public init(
        isExpanded: Binding<Bool>,
        displayTitle: String,
        activeAgent: MarkdownPillAgent?,
        onSubmit: @escaping (_ text: String, _ agent: MarkdownPillAgent) -> Void
    ) {
        self._isExpanded = isExpanded
        self.displayTitle = displayTitle
        self.activeAgent = activeAgent
        self.onSubmit = onSubmit
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
                activeAgent: activeAgent,
                onSubmit: onSubmit
            )
            .padding(.horizontal, Self.horizontalInset)
            .padding(.bottom, Self.bottomInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}
