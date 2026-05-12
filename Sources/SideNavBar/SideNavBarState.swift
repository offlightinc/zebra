import Combine
import Foundation

final class SideNavBarState: ObservableObject {
    @Published var selectedMode: SideNavBarMode

    init(selectedMode: SideNavBarMode = .goals) {
        self.selectedMode = selectedMode
    }
}
