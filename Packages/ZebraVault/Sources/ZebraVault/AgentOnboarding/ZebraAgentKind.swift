import Foundation

public enum ZebraAgentKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case claude
    case codex
    case antigravity

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .antigravity: return "Antigravity"
        }
    }

    public var binaryName: String {
        switch self {
        case .claude: return "claude"
        case .codex: return "codex"
        case .antigravity: return "agy"
        }
    }

    var versionArguments: [String] {
        switch self {
        case .claude, .codex, .antigravity:
            return ["--version"]
        }
    }

    var applicationSearchNames: [String] {
        switch self {
        case .claude:
            return ["Claude"]
        case .codex:
            return []
        case .antigravity:
            return ["Antigravity"]
        }
    }

    func executablePathCandidates(homeDirectoryPath: String) -> [String] {
        let localBin = "\(homeDirectoryPath)/.local/bin/\(binaryName)"
        switch self {
        case .claude:
            return [
                "/opt/homebrew/bin/\(binaryName)",
                "/usr/local/bin/\(binaryName)",
                localBin,
            ]
        case .codex:
            return [
                localBin,
                "/opt/homebrew/bin/\(binaryName)",
                "/usr/local/bin/\(binaryName)",
            ]
        case .antigravity:
            return [
                localBin,
                "/opt/homebrew/bin/\(binaryName)",
                "/usr/local/bin/\(binaryName)",
            ]
        }
    }

    func configHintPaths(homeDirectoryPath: String) -> [String] {
        switch self {
        case .claude:
            return [
                "\(homeDirectoryPath)/.claude",
                "\(homeDirectoryPath)/.claude.json",
            ]
        case .codex:
            return [
                "\(homeDirectoryPath)/.codex",
            ]
        case .antigravity:
            return [
                "\(homeDirectoryPath)/.config/antigravity",
                "\(homeDirectoryPath)/.local/share/antigravity",
            ]
        }
    }
}
