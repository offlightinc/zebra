import Combine
import Foundation

@MainActor
final class GoalsViewState: ObservableObject {
    static let pickerDefaultsKey = "verticalTabsSidebar.goals.picker"

    enum Picker: String, Codable, CaseIterable, Sendable {
        case outline
        case cadence
        case status
    }

    @Published var picker: Picker {
        didSet {
            guard !suppressPersistence else { return }
            UserDefaults.standard.set(picker.rawValue, forKey: Self.pickerDefaultsKey)
        }
    }

    private let suppressPersistence: Bool

    init(picker: Picker? = nil, suppressPersistence: Bool = false) {
        self.suppressPersistence = suppressPersistence
        if let picker {
            self.picker = picker
        } else if let raw = UserDefaults.standard.string(forKey: Self.pickerDefaultsKey),
                  let restored = Picker(rawValue: raw) {
            self.picker = restored
        } else {
            self.picker = .outline
        }
    }
}
