import Foundation

/// Zebra-side sidebar default values that diverge from cmux upstream.
///
/// These exist so the cmux `SessionPersistencePolicy` can stay byte-identical
/// to upstream while Zebra ships a wider initial sidebar (the mode rail eats
/// horizontal space the workspace list would otherwise have).
enum ZebraSidebarDefaults {
    /// First-launch sidebar width when no session snapshot exists. Cmux
    /// default is 200; Zebra picks 300 so the rail + workspace list both
    /// have comfortable space.
    static let defaultWidth: Double = 300
}
