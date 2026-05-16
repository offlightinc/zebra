import SwiftUI

struct VerticalTabsSidebarEmailContent: View {
    @ObservedObject var state: VerticalTabsSidebarModeState

    var body: some View {
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
