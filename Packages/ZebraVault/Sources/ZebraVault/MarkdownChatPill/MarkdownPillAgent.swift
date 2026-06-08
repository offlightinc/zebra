import Foundation

public enum MarkdownPillAgent: String, CaseIterable, Identifiable, Sendable {
    case codex
    case claude
    case antigravity

    public var id: String { rawValue }

    public static func defaultAgent(
        preferenceStore: ZebraAgentPreferenceStore = ZebraAgentPreferenceStore()
    ) -> MarkdownPillAgent {
        guard let primaryAgent = preferenceStore.load().primaryAgent else {
            return .codex
        }
        return MarkdownPillAgent(agentKind: primaryAgent)
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
}
