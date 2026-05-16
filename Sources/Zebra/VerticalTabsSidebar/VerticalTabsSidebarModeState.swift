import Combine
import Foundation

@MainActor
final class VerticalTabsSidebarModeState: ObservableObject {
    static let listVisibleDefaultsKey = "verticalTabsSidebar.modeListVisible"

    @Published var selectedMode: VerticalTabsSidebarMode
    @Published var listVisible: Bool {
        didSet {
            guard !suppressPersistence else { return }
            UserDefaults.standard.set(listVisible, forKey: Self.listVisibleDefaultsKey)
        }
    }
    @Published var activeMarkdownFilePaths: Set<String>

    private let suppressPersistence: Bool

    init(
        selectedMode: VerticalTabsSidebarMode = .terminal,
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

    func handleIconClick(_ mode: VerticalTabsSidebarMode) {
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
