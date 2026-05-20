import SwiftUI

/// Central listing of every Settings section Zebra contributes. Kept in one
/// place so `ZebraServices.injectIntoEnvironment` doesn't have to know about
/// individual section types — each entry registers (id, descriptor, factory)
/// together, and adding a new section is a single tuple append.
enum ZebraSettingsExtensionRegistry {
    /// Source-of-truth list. Each tuple wires together the sidebar descriptor
    /// (the `SettingsExtensionSection` that drives sidebar + search) and the
    /// matching detail-view factory closure. Empty until callers append
    /// concrete section/view pairs (see commits adding individual Zebra
    /// settings surfaces).
    private static let entries: [(SettingsExtensionSection, () -> AnyView)] = []

    static func sections() -> [SettingsExtensionSection] {
        entries.map { $0.0 }
    }

    static func viewFactory() -> SettingsExtensionViewFactory {
        return { id in
            for (section, makeView) in entries where section.id == id {
                return makeView()
            }
            return nil
        }
    }
}
