import SwiftUI

public struct VerticalTabsSidebarEmailContent: View {
    @ObservedObject public var state: VerticalTabsSidebarModeState

    public init(state: VerticalTabsSidebarModeState) {
        self.state = state
    }

    public var body: some View {
        EmailSidebarView(
            threads: EmailSidebarSampleData.threads,
            userLabels: EmailSidebarSampleData.labels,
            onCreateLabel: { name in
                EmailUserLabel(id: "local-\(UUID().uuidString)", name: name, color: BrainPersonColor.color(for: name))
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1)
        }
        .accessibilityIdentifier("VerticalTabsSidebarEmailContent")
    }
}
