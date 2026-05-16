import Foundation

public struct PersonEntry: VaultSubdirEntry {
    public let absolutePath: String
    public let slug: String
    public let displayName: String

    public var id: String { absolutePath }
}
