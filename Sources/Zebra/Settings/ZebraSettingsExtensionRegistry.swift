import SwiftUI

/// Central listing of every Settings section Zebra contributes. Kept in one
/// place so `ZebraServices.injectIntoEnvironment` doesn't have to know about
/// individual section types — each entry registers (id, descriptor, factory)
/// together, and adding a new section is a single tuple append.
enum ZebraSettingsExtensionRegistry {
    /// Source-of-truth list. Each tuple wires together the sidebar descriptor
    /// (the `SettingsExtensionSection` that drives sidebar + search) and the
    /// matching detail-view factory closure.
    private static let entries: [(SettingsExtensionSection, () -> AnyView)] = [
        (
            SettingsExtensionSection(
                id: "zebra.clawvisor",
                title: String(
                    localized: "settings.section.clawvisor",
                    defaultValue: "Clawvisor"
                ),
                symbolName: "envelope.badge.shield.half.filled",
                searchText: "clawvisor gmail email brain agent token rpc sync"
            ),
            { AnyView(ZebraClawvisorSettingsView()) }
        )
    ]

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
