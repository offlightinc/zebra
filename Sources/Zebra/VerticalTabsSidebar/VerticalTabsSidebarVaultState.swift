import Foundation

struct VerticalTabsSidebarVault: Identifiable, Hashable {
    var id: String { path }
    let name: String
    let path: String
}

@MainActor
final class VerticalTabsSidebarVaultState: ObservableObject {
    private static let vaultPathsDefaultsKey = "verticalTabsSidebar.vaultPaths"
    private static let selectedVaultPathDefaultsKey = "verticalTabsSidebar.selectedVaultPath"

    @Published private(set) var vaults: [VerticalTabsSidebarVault]
    @Published var selectedVaultPath: String? {
        didSet {
            guard selectedVaultPath != oldValue else { return }
            persist()
        }
    }

    var selectedVault: VerticalTabsSidebarVault? {
        guard let selectedVaultPath else { return nil }
        return vaults.first { $0.path == selectedVaultPath }
    }

    init(
        vaultPaths: [String]? = nil,
        selectedVaultPath: String? = nil
    ) {
        let resolvedPaths = vaultPaths ?? Self.loadVaultPaths()
        self.vaults = Self.makeVaults(paths: resolvedPaths)

        let restoredSelectedPath = selectedVaultPath
            ?? UserDefaults.standard.string(forKey: Self.selectedVaultPathDefaultsKey)
        if let restoredSelectedPath,
           self.vaults.contains(where: { $0.path == restoredSelectedPath }) {
            self.selectedVaultPath = restoredSelectedPath
        } else {
            self.selectedVaultPath = self.vaults.first?.path
        }
    }

    func selectVault(_ vault: VerticalTabsSidebarVault) {
        selectedVaultPath = vault.path
    }

    func addVault(url: URL) {
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
            guard !path.isEmpty, !seen.contains(path), isDirectory(path) else { return nil }
            seen.insert(path)
            return path
        }
    }

    private static func defaultVaultPathCandidates() -> [String] {
        let home = NSHomeDirectory()
        return [
            "\(home)/brain",
            "\(home)/b-brain",
            "\(home)/b-brain-offlight",
        ]
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
