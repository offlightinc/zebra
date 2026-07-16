import Foundation

public enum ZebraChatPillPanePlacement: String, CaseIterable, Identifiable, Sendable {
    case below
    case right

    public var id: String { rawValue }
}

public enum ZebraChatPillPanePlacementSettings {
    public static let key = "zebra.chatPill.agentPanePlacement"
    public static let defaultPlacement: ZebraChatPillPanePlacement = .below

    public static func placement(for rawValue: String?) -> ZebraChatPillPanePlacement {
        guard let rawValue,
              let placement = ZebraChatPillPanePlacement(rawValue: rawValue) else {
            return defaultPlacement
        }
        return placement
    }

    public static func resolvedPlacement(
        defaults: UserDefaults = .standard
    ) -> ZebraChatPillPanePlacement {
        placement(for: defaults.string(forKey: key))
    }
}
