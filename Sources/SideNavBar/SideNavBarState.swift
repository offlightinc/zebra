import Combine
import Foundation

final class SideNavBarState: ObservableObject {
    @Published var selectedMode: SideNavBarMode
    @Published var selectedMarkdownFilePath: String?

    init(selectedMode: SideNavBarMode = .goals, selectedMarkdownFilePath: String? = nil) {
        self.selectedMode = selectedMode
        self.selectedMarkdownFilePath = selectedMarkdownFilePath
    }
}
