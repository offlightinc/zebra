import Foundation

struct PersonEntry: VaultSubdirEntry {
    let absolutePath: String
    let slug: String
    let displayName: String

    var id: String { absolutePath }
}
