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

    private let defaults: UserDefaults
    private let homeDirectoryPath: String

    @Published public private(set) var vaults: [VerticalTabsSidebarVault]
    @Published public private(set) var selectedVaultWasExplicitlyChosen: Bool
    @Published public var selectedVaultPath: String? {
        didSet {
            guard selectedVaultPath != oldValue else { return }
            selectedVaultWasExplicitlyChosen = selectedVaultPath != nil
            persist()
        }
    }

    public var selectedVault: VerticalTabsSidebarVault? {
        guard let selectedVaultPath else { return nil }
        return vaults.first { $0.path == selectedVaultPath }
    }

    public init(
        vaultPaths: [String]? = nil,
        selectedVaultPath: String? = nil,
        defaults: UserDefaults = .standard,
        homeDirectoryPath: String = NSHomeDirectory()
    ) {
        self.defaults = defaults
        self.homeDirectoryPath = Self.normalizedPath(homeDirectoryPath)
        self.selectedVaultWasExplicitlyChosen = false

        let resolvedPaths = vaultPaths ?? Self.loadVaultPaths(
            defaults: defaults,
            homeDirectoryPath: self.homeDirectoryPath
        )
        self.vaults = Self.makeVaults(paths: resolvedPaths)

        let restoredSelectedPath = selectedVaultPath
            ?? defaults.string(forKey: Self.selectedVaultPathDefaultsKey)
        let normalizedSelectedPath = restoredSelectedPath.map(Self.normalizedPath)
        if let normalizedSelectedPath,
           Self.isDirectory(normalizedSelectedPath) {
            if !self.vaults.contains(where: { $0.path == normalizedSelectedPath }) {
                self.vaults.append(Self.makeVault(path: normalizedSelectedPath))
                self.vaults.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
            self.selectedVaultPath = normalizedSelectedPath
            self.selectedVaultWasExplicitlyChosen = true
        } else if let homeDefaultPath = Self.homeDefaultVaultPath(homeDirectoryPath: self.homeDirectoryPath),
                  self.vaults.contains(where: { $0.path == homeDefaultPath }) {
            self.selectedVaultPath = homeDefaultPath
            self.selectedVaultWasExplicitlyChosen = false
        } else {
            self.selectedVaultPath = self.vaults.first?.path
            self.selectedVaultWasExplicitlyChosen = false
        }
    }

    public func selectVault(_ vault: VerticalTabsSidebarVault) {
        selectedVaultWasExplicitlyChosen = true
        selectedVaultPath = vault.path
    }

    public func addVault(url: URL) {
        let path = Self.normalizedPath(url.path)
        guard !path.isEmpty else { return }
        if !vaults.contains(where: { $0.path == path }) {
            vaults.append(Self.makeVault(path: path))
            vaults.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        selectedVaultWasExplicitlyChosen = true
        selectedVaultPath = path
        persist()
    }

    private func persist() {
        defaults.set(vaults.map(\.path), forKey: Self.vaultPathsDefaultsKey)
        if let selectedVaultPath {
            defaults.set(selectedVaultPath, forKey: Self.selectedVaultPathDefaultsKey)
        } else {
            defaults.removeObject(forKey: Self.selectedVaultPathDefaultsKey)
        }
    }

    private static func loadVaultPaths(
        defaults: UserDefaults,
        homeDirectoryPath: String
    ) -> [String] {
        let stored = defaults.stringArray(forKey: vaultPathsDefaultsKey) ?? []
        let candidates = stored + defaultVaultPathCandidates(homeDirectoryPath: homeDirectoryPath)
        var seen = Set<String>()
        return candidates.compactMap { candidate in
            let path = normalizedPath(candidate)
            guard !path.isEmpty,
                  !seen.contains(path),
                  isDirectory(path) else { return nil }
            seen.insert(path)
            return path
        }
    }

    private static func defaultVaultPathCandidates(homeDirectoryPath: String) -> [String] {
        guard let homeDefaultPath = homeDefaultVaultPath(homeDirectoryPath: homeDirectoryPath) else { return [] }
        return [homeDefaultPath]
    }

    private static func homeDefaultVaultPath(homeDirectoryPath: String) -> String? {
        let normalized = normalizedPath(homeDirectoryPath)
        guard !normalized.isEmpty, isDirectory(normalized) else { return nil }
        return normalized
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
