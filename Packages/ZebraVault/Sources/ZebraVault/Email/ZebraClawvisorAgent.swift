import SwiftUI

/// Agent target for Clawvisor's "Connect an Agent" flow. Mirrors the four
/// tabs the Clawvisor dashboard exposes (Claude Code, Claude Desktop,
/// OpenClaw/Hermes, Other Agents). Only Claude Code is wired right now —
/// the other three render as disabled "Coming soon" rows in the picker.
public enum ZebraClawvisorAgent: String, CaseIterable, Identifiable, Sendable {
    case claudeCode
    case claudeDesktop
    case openClawHermes
    case otherAgents

    public var id: String { rawValue }

    /// Short label for the dropdown selector / row.
    public var label: String {
        switch self {
        case .claudeCode:
            return "Claude Code"
        case .claudeDesktop:
            return "Claude Desktop"
        case .openClawHermes:
            return "OpenClaw / Hermes"
        case .otherAgents:
            return "Other agents"
        }
    }

    /// SF Symbol shown next to the label in the dropdown. Matches the
    /// chat pill's `MarkdownPillAgentDot` styling: small filled glyph.
    public var symbolName: String {
        switch self {
        case .claudeCode:
            return "terminal"
        case .claudeDesktop:
            return "macwindow"
        case .openClawHermes:
            return "shippingbox"
        case .otherAgents:
            return "ellipsis.circle"
        }
    }

    /// Two-line vendor · tagline shown under the label in the picker.
    /// Matches md-app.jsx's `AGENTS.desc` styling — monospaced textDim.
    public var desc: String {
        switch self {
        case .claudeCode: return "Anthropic · CLI"
        case .claudeDesktop: return "Anthropic · desktop"
        case .openClawHermes: return "OpenClaw · proxy"
        case .otherAgents: return "Custom · any agent"
        }
    }

    /// Only Claude Code has a wired-up onboarding flow today. The other
    /// three render disabled in the picker.
    public var isAvailable: Bool {
        switch self {
        case .claudeCode:
            return true
        case .claudeDesktop, .openClawHermes, .otherAgents:
            return false
        }
    }

    public static let `default`: ZebraClawvisorAgent = .claudeCode
}

/// Rich agent row used inside the email "Connect with" dropdown. Mirrors
/// md-app.jsx::AgentSelector menu rows:
///   [SF Symbol]  label              [Coming soon | nothing]
///                vendor · tagline
/// Active row tints with the chat-pill accent mint; disabled rows fade
/// to muted foreground. Email picker keeps the plain SF Symbol glyph (no
/// colored rounded-square dot) — the chat pill is the canonical visual
/// home for that glyph treatment.
struct ZebraClawvisorAgentMenuRow: View {
    let agent: ZebraClawvisorAgent
    let active: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: agent.symbolName)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(agent.isAvailable ? BVColor.fg : BVColor.fgFaint)
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(agent.label)
                    .font(.system(size: 12.5))
                    .foregroundColor(agent.isAvailable ? BVColor.fg : BVColor.fgMute)
                Text(agent.desc)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(BVColor.fgFaint)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if !agent.isAvailable {
                Text(String(
                    localized: "email.connect.agent.comingSoon",
                    defaultValue: "Coming soon"
                ))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(BVColor.fgFaint)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(BVColor.bgInput)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(BVColor.border)
                        )
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(active ? MarkdownPillPalette.accent.opacity(0.10) : .clear)
        )
        .contentShape(Rectangle())
    }
}
