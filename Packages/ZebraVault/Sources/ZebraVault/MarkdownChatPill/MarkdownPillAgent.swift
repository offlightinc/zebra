import Foundation

public enum MarkdownPillAgent: String, CaseIterable, Identifiable, Sendable {
    case codex
    case claude
    case antigravity

    public var id: String { rawValue }

    public static func defaultAgent(
        preferenceStore: ZebraAgentPreferenceStore = ZebraAgentPreferenceStore()
    ) -> MarkdownPillAgent {
        primaryAgent(preferenceStore: preferenceStore) ?? .codex
    }

    public static func primaryAgent(
        preferenceStore: ZebraAgentPreferenceStore = ZebraAgentPreferenceStore()
    ) -> MarkdownPillAgent? {
        preferenceStore.load().primaryAgent.map(MarkdownPillAgent.init(agentKind:))
    }

    public init(agentKind: ZebraAgentKind) {
        switch agentKind {
        case .codex:
            self = .codex
        case .claude:
            self = .claude
        case .antigravity:
            self = .antigravity
        }
    }

    public var agentKind: ZebraAgentKind {
        switch self {
        case .codex:
            return .codex
        case .claude:
            return .claude
        case .antigravity:
            return .antigravity
        }
    }

    /// The CLI binary name expected on $PATH. See
    /// `MarkdownChatPillCommand` for the shell launch + first-prompt
    /// protocol.
    var binaryName: String {
        agentKind.binaryName
    }

    var label: String {
        switch self {
        case .codex: return "codex"
        case .claude: return "claude"
        case .antigravity: return "antigravity"
        }
    }

    var displayName: String {
        agentKind.displayName
    }

    var symbolName: String {
        switch self {
        case .codex:
            return "terminal"
        case .claude:
            return "terminal"
        case .antigravity:
            return "sparkles"
        }
    }
}
