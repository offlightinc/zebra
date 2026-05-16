import Foundation

enum MarkdownPillAgent: String, CaseIterable, Identifiable {
    case codex
    case claude
    case gemini

    var id: String { rawValue }

    /// The CLI binary name expected on $PATH. See
    /// `MarkdownChatPillCommand` for the shell launch + first-prompt
    /// protocol.
    var binaryName: String {
        switch self {
        case .codex: return "codex"
        case .claude: return "claude"
        case .gemini: return "gemini"
        }
    }

    var label: String {
        switch self {
        case .codex: return "codex"
        case .claude: return "claude"
        case .gemini: return "gemini"
        }
    }
}
