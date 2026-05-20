import Combine
import Foundation

@MainActor
public final class GoalsViewState: ObservableObject {
    public static let pickerDefaultsKey = "verticalTabsSidebar.goals.picker"

    public enum Picker: String, Codable, CaseIterable, Sendable {
        case outline
        case cadence
        case status
    }

    @Published public var picker: Picker {
        didSet {
            guard !suppressPersistence else { return }
            UserDefaults.standard.set(picker.rawValue, forKey: Self.pickerDefaultsKey)
        }
    }

    private let suppressPersistence: Bool

    public init(picker: Picker? = nil, suppressPersistence: Bool = false) {
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
