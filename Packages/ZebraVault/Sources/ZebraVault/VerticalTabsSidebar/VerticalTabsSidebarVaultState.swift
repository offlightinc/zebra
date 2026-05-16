import Foundation

public struct VerticalTabsSidebarVault: Identifiable, Hashable {
    public var id: String { path }
    public let name: String
    public let path: String
}

@MainActor
public final class VerticalTabsSidebarVaultState: ObservableObject {
    private static let vaultPathsDefaultsKey = "verticalTabsSidebar.vaultPaths"
    private static let selectedVaultPathDefaultsKey = "verticalTabsSidebar.selectedVaultPath"

    @Published public private(set) var vaults: [VerticalTabsSidebarVault]
    @Published public var selectedVaultPath: String? {
        didSet {
            guard selectedVaultPath != oldValue else { return }
            persist()
        }
    }

    public var selectedVault: VerticalTabsSidebarVault? {
        guard let selectedVaultPath else { return nil }
        return vaults.first { $0.path == selectedVaultPath }
    }

    public init(
        vaultPaths: [String]? = nil,
        selectedVaultPath: String? = nil
    ) {
        let resolvedPaths = vaultPaths ?? Self.loadVaultPaths()
        self.vaults = Self.makeVaults(paths: resolvedPaths)

        let restoredSelectedPath = selectedVaultPath
            ?? UserDefaults.standard.string(forKey: Self.selectedVaultPathDefaultsKey)
        if Self.shouldPreferOfflightVault(over: restoredSelectedPath),
           let preferredDefaultPath = Self.preferredDefaultVaultPath(in: self.vaults) {
            self.selectedVaultPath = preferredDefaultPath
        } else if let restoredSelectedPath,
           self.vaults.contains(where: { $0.path == restoredSelectedPath }) {
            self.selectedVaultPath = restoredSelectedPath
        } else if let preferredDefaultPath = Self.preferredDefaultVaultPath(in: self.vaults) {
            self.selectedVaultPath = preferredDefaultPath
        } else {
            self.selectedVaultPath = self.vaults.first?.path
        }
    }

    public func selectVault(_ vault: VerticalTabsSidebarVault) {
        selectedVaultPath = vault.path
    }

    public func addVault(url: URL) {
        let path = Self.normalizedPath(url.path)
        guard !path.isEmpty else { return }
        if !vaults.contains(where: { $0.path == path }) {
            vaults.append(Self.makeVault(path: path))
            vaults.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        selectedVaultPath = path
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(vaults.map(\.path), forKey: Self.vaultPathsDefaultsKey)
        if let selectedVaultPath {
            UserDefaults.standard.set(selectedVaultPath, forKey: Self.selectedVaultPathDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.selectedVaultPathDefaultsKey)
        }
    }

    private static func loadVaultPaths() -> [String] {
        let defaults = UserDefaults.standard
        let stored = defaults.stringArray(forKey: vaultPathsDefaultsKey) ?? []
        let candidates = stored + defaultVaultPathCandidates()
        var seen = Set<String>()
        return candidates.compactMap { candidate in
            let path = normalizedPath(candidate)
            guard !path.isEmpty,
                  !seen.contains(path),
                  !isDeprecatedDefaultVaultPath(path),
                  isDirectory(path) else { return nil }
            seen.insert(path)
            return path
        }
    }

    private static func defaultVaultPathCandidates() -> [String] {
        let home = NSHomeDirectory()
        return [
            "\(home)/brain-offlight",
            "\(home)/b-brain",
        ]
    }

    private static func preferredDefaultVaultPath(in vaults: [VerticalTabsSidebarVault]) -> String? {
        let home = NSHomeDirectory()
        let preferredPath = normalizedPath("\(home)/brain-offlight")
        return vaults.first { $0.path == preferredPath }?.path
    }

    private static func shouldPreferOfflightVault(over restoredSelectedPath: String?) -> Bool {
        guard let restoredSelectedPath else { return true }
        let home = NSHomeDirectory()
        return normalizedPath(restoredSelectedPath) == normalizedPath("\(home)/b-brain")
    }

    private static func isDeprecatedDefaultVaultPath(_ path: String) -> Bool {
        let home = NSHomeDirectory()
        let deprecatedPaths = [
            normalizedPath("\(home)/brain"),
            normalizedPath("\(home)/b-brain-offlight"),
        ]
        return deprecatedPaths.contains(normalizedPath(path))
    }

    private static func makeVaults(paths: [String]) -> [VerticalTabsSidebarVault] {
        paths.map { makeVault(path: normalizedPath($0)) }
            .filter { !$0.path.isEmpty }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func makeVault(path: String) -> VerticalTabsSidebarVault {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        let lastPathComponent = url.lastPathComponent
        let name = lastPathComponent.isEmpty ? path : lastPathComponent
        return VerticalTabsSidebarVault(name: name, path: path)
    }

    private static func normalizedPath(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        let standardized = URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL.path
        guard standardized.count > 1, standardized.hasSuffix("/") else { return standardized }
        return String(standardized.dropLast())
    }

    private static func isDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
