import SwiftUI

/// A Settings sidebar section contributed by a non-cmux module (i.e. Zebra).
///
/// cmux's Settings window walks this list — injected through the env values
/// below — in addition to the hardcoded `SettingsNavigationTarget` cases.
/// The detail view comes from the registered `\.settingsExtensionViewFactory`,
/// keyed on the same `id`. cmux common code never names a Zebra concrete
/// view type.
///
/// Modeled after `\.customPanelViewFactory` (see `PanelContentView.swift`).
///
/// Lives under `Sources/Zebra/` (not `Packages/ZebraVault/`) because cmux's
/// `SettingsRootView` / `SettingsView` (in `cmuxApp.swift`) need to read these
/// environment values and call the `SettingsSearchIndex` / `SettingsNavigationRequest`
/// extension methods declared here. Both live in the cmux target, so internal
/// access just works.
struct SettingsExtensionSection: Identifiable, Equatable {
    let id: String
    let title: String
    let symbolName: String
    let searchText: String

    static func == (lhs: SettingsExtensionSection, rhs: SettingsExtensionSection) -> Bool {
        lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.symbolName == rhs.symbolName
            && lhs.searchText == rhs.searchText
    }
}

typealias SettingsExtensionViewFactory = (String) -> AnyView?

private struct SettingsExtensionSectionsKey: EnvironmentKey {
    static let defaultValue: [SettingsExtensionSection] = []
}

private struct SettingsExtensionViewFactoryKey: EnvironmentKey {
    static let defaultValue: SettingsExtensionViewFactory? = nil
}

extension EnvironmentValues {
    var settingsExtensionSections: [SettingsExtensionSection] {
        get { self[SettingsExtensionSectionsKey.self] }
        set { self[SettingsExtensionSectionsKey.self] = newValue }
    }

    var settingsExtensionViewFactory: SettingsExtensionViewFactory? {
        get { self[SettingsExtensionViewFactoryKey.self] }
        set { self[SettingsExtensionViewFactoryKey.self] = newValue }
    }
}

// MARK: - Navigation request extension

/// Notification payload for an extension destination. Mirrors
/// `SettingsNavigationDestination` but carries an extension id instead of an
/// enum target.
struct SettingsExtensionDestination {
    let extensionID: String
    let anchorID: String
    let shouldHighlight: Bool
}

extension SettingsNavigationRequest {
    // Notification userInfo keys. Local to this extension; the cmux file
    // (`SettingsNavigation.swift`) declares its own private constants for the
    // builtin target/anchor/highlight keys with the same string values
    // ("anchor", "highlight"). Keep these in sync if upstream renames them.
    private static let extensionKey = "extensionID"
    private static let extensionAnchorKey = "anchor"
    private static let extensionHighlightKey = "highlight"

    /// Variant of `post(_:anchorID:highlight:)` for sections contributed by
    /// `SettingsExtensionSection`. The notification carries the extension id
    /// in place of an enum target.
    static func post(extensionID: String, anchorID: String? = nil, highlight: Bool = false) {
        NotificationCenter.default.post(
            name: notificationName,
            object: nil,
            userInfo: [
                extensionKey: extensionID,
                extensionAnchorKey: anchorID ?? SettingsSearchIndex.sectionID(forExtensionID: extensionID),
                extensionHighlightKey: highlight
            ]
        )
    }

    /// Returns the extension destination for a request whose target is a
    /// `SettingsExtensionSection`, or `nil` if the request is for a builtin
    /// `SettingsNavigationTarget`. Callers check both this and
    /// `destination(from:)` so either flavor of request can be handled.
    static func extensionDestination(from notification: Notification) -> SettingsExtensionDestination? {
        guard let extensionID = notification.userInfo?[extensionKey] as? String else {
            return nil
        }
        let anchorID = notification.userInfo?[extensionAnchorKey] as? String
        let shouldHighlight = notification.userInfo?[extensionHighlightKey] as? Bool ?? false
        return SettingsExtensionDestination(
            extensionID: extensionID,
            anchorID: anchorID ?? SettingsSearchIndex.sectionID(forExtensionID: extensionID),
            shouldHighlight: shouldHighlight
        )
    }
}

// MARK: - Search index extension

extension SettingsSearchIndex {
    /// Stable sidebar entry id for a `SettingsExtensionSection`. The prefix
    /// is what `selectSidebarEntry` / `applySettingsNavigation` key off to
    /// route extension entries through the extension-aware path.
    static func sectionID(forExtensionID extensionID: String) -> String {
        "ext-section:\(extensionID)"
    }

    /// Whether a sidebar entry id was produced by `sectionID(forExtensionID:)`.
    static func isExtensionEntryID(_ id: String) -> Bool {
        id.hasPrefix("ext-section:")
    }

    /// Extracts the extension id from an entry id produced by
    /// `sectionID(forExtensionID:)`. Returns `nil` for builtin entry ids.
    static func extensionID(fromEntryID entryID: String) -> String? {
        let prefix = "ext-section:"
        guard entryID.hasPrefix(prefix) else { return nil }
        return String(entryID.dropFirst(prefix.count))
    }

    /// Builtin search results + extension sections combined. Extension
    /// entries are appended after the builtin ones in both empty-query and
    /// search modes.
    ///
    /// The extension `SettingsSearchEntry` instances use a dummy `.account`
    /// target — selection routing (in `SettingsRootView.selectSidebarEntry`)
    /// keys off `isExtensionEntryID(entry.id)` instead, so the dummy is
    /// never observed by builtin navigation code.
    static func entries(
        matching query: String,
        extras: [SettingsExtensionSection]
    ) -> [SettingsSearchEntry] {
        let builtin = entries(matching: query)
        let extensionEntries = filterExtensionEntries(
            extensionEntries(for: extras),
            query: query
        )
        return builtin + extensionEntries
    }

    private static func extensionEntries(
        for extras: [SettingsExtensionSection]
    ) -> [SettingsSearchEntry] {
        extras.map { section in
            SettingsSearchEntry(
                id: sectionID(forExtensionID: section.id),
                kind: .section,
                target: .account, // dummy — see entries(matching:extras:) doc
                title: section.title,
                subtitle: nil,
                symbolName: section.symbolName,
                searchText: "\(section.id) \(section.searchText)"
            )
        }
    }

    private static func filterExtensionEntries(
        _ entries: [SettingsSearchEntry],
        query: String
    ) -> [SettingsSearchEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return entries }
        let normalizedQuery = normalized(trimmed)
        let tokens = normalizedQuery
            .split { character in
                character.unicodeScalars.allSatisfy { scalar in
                    CharacterSet.whitespacesAndNewlines.contains(scalar)
                        || CharacterSet.punctuationCharacters.contains(scalar)
                }
            }
            .map(String.init)
        return entries.filter { entry in
            tokens.allSatisfy { token in entry.normalizedSearchText.contains(token) }
        }
    }
}
