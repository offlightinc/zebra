import Combine
import Foundation

@MainActor
final class SideNavBarState: ObservableObject {
    static let listVisibleDefaultsKey = "sideNavBar.listVisible"

    @Published var selectedMode: SideNavBarMode
    @Published var listVisible: Bool {
        didSet {
            guard !suppressPersistence else { return }
            UserDefaults.standard.set(listVisible, forKey: Self.listVisibleDefaultsKey)
        }
    }
    @Published var activeMarkdownFilePaths: Set<String>

    private let suppressPersistence: Bool

    init(
        selectedMode: SideNavBarMode = .goals,
        listVisible: Bool? = nil,
        activeMarkdownFilePaths: Set<String> = [],
        suppressPersistence: Bool = false
    ) {
        self.suppressPersistence = suppressPersistence
        self.selectedMode = selectedMode
        let restored: Bool
        if let listVisible {
            restored = listVisible
        } else if UserDefaults.standard.object(forKey: Self.listVisibleDefaultsKey) != nil {
            restored = UserDefaults.standard.bool(forKey: Self.listVisibleDefaultsKey)
        } else {
            restored = true
        }
        self.listVisible = restored
        self.activeMarkdownFilePaths = activeMarkdownFilePaths
    }

    func handleIconClick(_ mode: SideNavBarMode) {
        if selectedMode == mode {
            listVisible.toggle()
        } else {
            selectedMode = mode
            if !listVisible {
                listVisible = true
            }
        }
    }
}
