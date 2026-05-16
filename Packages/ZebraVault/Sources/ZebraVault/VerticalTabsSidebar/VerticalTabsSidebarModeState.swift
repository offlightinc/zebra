import Combine
import Foundation

@MainActor
public final class VerticalTabsSidebarModeState: ObservableObject {
    public static let listVisibleDefaultsKey = "verticalTabsSidebar.modeListVisible"

    @Published public var selectedMode: VerticalTabsSidebarMode
    @Published public var listVisible: Bool {
        didSet {
            guard !suppressPersistence else { return }
            UserDefaults.standard.set(listVisible, forKey: Self.listVisibleDefaultsKey)
        }
    }
    @Published public var activeMarkdownFilePaths: Set<String>

    private let suppressPersistence: Bool

    public init(
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
