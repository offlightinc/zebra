import SwiftUI

/// Captures the email sidebar agent picker trigger button's bounds so the
/// dropdown can be rendered at `disconnectedContent`'s root level (outside
/// the inner VStack/Spacer layout). Scoped `fileprivate` so it can't leak
/// anchors into the chat pill's `AgentButtonAnchorKey` if either view ever
/// ends up nested inside the other.
fileprivate struct EmailAgentButtonAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

public struct VerticalTabsSidebarEmailContent: View {
    @ObservedObject public var state: VerticalTabsSidebarModeState
    private let threads: [EmailThreadItem]?
    private let userLabels: [EmailUserLabel]?
    private let isConnected: Bool
    private let isLoading: Bool
    private let isSyncing: Bool
    private let errorMessage: String?
    private let connectionRepairState: ZebraEmailConnectionRepairState?
    private let selectedThreadId: String?
    private let onConnect: ((ZebraClawvisorAgent) -> Void)?
    private let onRefresh: (() -> Void)?
    private let onSelectThread: ((EmailThreadItem) -> Void)?
    private let onCreateLabel: ((String) -> EmailUserLabel)?

    @State private var selectedAgent: ZebraClawvisorAgent = .default
    @State private var agentMenuOpen: Bool = false

    public init(state: VerticalTabsSidebarModeState) {
        self.state = state
        self.threads = nil
        self.userLabels = nil
        self.isConnected = true
        self.isLoading = false
        self.isSyncing = false
        self.errorMessage = nil
        self.connectionRepairState = nil
        self.selectedThreadId = nil
        self.onConnect = nil
        self.onRefresh = nil
        self.onSelectThread = nil
        self.onCreateLabel = nil
    }

    public init(
        state: VerticalTabsSidebarModeState,
        threads: [EmailThreadItem],
        userLabels: [EmailUserLabel],
        isConnected: Bool,
        isLoading: Bool,
        isSyncing: Bool,
        errorMessage: String?,
        connectionRepairState: ZebraEmailConnectionRepairState?,
        selectedThreadId: String?,
        onConnect: @escaping (ZebraClawvisorAgent) -> Void,
        onRefresh: @escaping () -> Void,
        onSelectThread: @escaping (EmailThreadItem) -> Void,
        onCreateLabel: @escaping (String) -> EmailUserLabel
    ) {
        self.state = state
        self.threads = threads
        self.userLabels = userLabels
        self.isConnected = isConnected
        self.isLoading = isLoading
        self.isSyncing = isSyncing
        self.errorMessage = errorMessage
        self.connectionRepairState = connectionRepairState
        self.selectedThreadId = selectedThreadId
        self.onConnect = onConnect
        self.onRefresh = onRefresh
        self.onSelectThread = onSelectThread
        self.onCreateLabel = onCreateLabel
    }

    public var body: some View {
        content
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1)
        }
        .accessibilityIdentifier("VerticalTabsSidebarEmailContent")
    }

    @ViewBuilder
    private var content: some View {
        let resolvedThreads = threads ?? EmailSidebarSampleData.threads
        if let connectionRepairState, resolvedThreads.isEmpty {
            repairContent(connectionRepairState)
        } else if let errorMessage, !errorMessage.isEmpty, resolvedThreads.isEmpty {
            errorContent(errorMessage)
        } else if !isConnected && resolvedThreads.isEmpty {
            disconnectedContent
        } else {
            EmailSidebarView(
                threads: resolvedThreads,
                userLabels: userLabels ?? EmailSidebarSampleData.labels,
                selectedThreadId: selectedThreadId,
                isLoading: isLoading,
                isSyncing: isSyncing,
                onSelectThread: onSelectThread ?? { _ in },
                onRefresh: onRefresh,
                onCreateLabel: onCreateLabel ?? { name in
                    EmailUserLabel(id: "local-\(UUID().uuidString)", name: name, color: BrainPersonColor.color(for: name))
                }
            )
        }
    }

    private var disconnectedContent: some View {
        GeometryReader { geo in
            VStack(spacing: 10) {
                Spacer(minLength: 0)
                Image(systemName: "envelope.badge")
                    .font(.system(size: 22))
                    .foregroundColor(BVColor.fgFaint)
                Text(String(localized: "email.connect.title", defaultValue: "Gmail 연결"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(BVColor.fgMute)
                    .lineLimit(1)
                Text(String(localized: "email.connect.subtitle", defaultValue: "Clawvisor가 받은편지함을 동기화합니다"))
                    .font(.system(size: 11))
                    .foregroundColor(BVColor.fgFaint)
                    .lineLimit(1)
                    .padding(.horizontal, 16)
                connectButton
                    .frame(width: max(80, geo.size.width * 2 / 3))
                agentSelectorButton
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(BVColor.bg)
        .overlayPreferenceValue(EmailAgentButtonAnchorKey.self) { anchor in
            agentDropdownOverlay(anchor: anchor)
        }
    }

    /// Renders the agent picker dropdown BELOW the agent button. Anchored
    /// via `EmailAgentButtonAnchorKey`. Lives at `disconnectedContent`'s root so
    /// it doesn't get tangled in the inner VStack/Spacer layout.
    @ViewBuilder
    private func agentDropdownOverlay(anchor: Anchor<CGRect>?) -> some View {
        GeometryReader { geo in
            if let anchor, agentMenuOpen {
                let rect = geo[anchor]
                let dropdownWidth: CGFloat = 240
                let gap: CGFloat = 6
                ZStack(alignment: .topLeading) {
                    Color.clear
                    agentDropdownPanel
                        .offset(x: max(0, min(geo.size.width - dropdownWidth, rect.midX - dropdownWidth / 2)))
                }
                .frame(
                    width: geo.size.width,
                    height: max(0, geo.size.height - rect.maxY - gap),
                    alignment: .topLeading
                )
                .offset(y: rect.maxY + gap)
                .allowsHitTesting(true)
            }
        }
        .dismissOnOutsideMouseUp(isPresented: $agentMenuOpen)
    }

    private var agentDropdownPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(ZebraClawvisorAgent.allCases) { option in
                Button {
                    if option.isAvailable {
                        selectedAgent = option
                        agentMenuOpen = false
                    }
                } label: {
                    ZebraClawvisorAgentMenuRow(
                        agent: option,
                        active: option == selectedAgent
                    )
                }
                .buttonStyle(.plain)
                .disabled(!option.isAvailable)
            }
        }
        .padding(4)
        .frame(width: 240)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(MarkdownPillPalette.popoverBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(MarkdownPillPalette.borderStrong, lineWidth: 1)
        )
        .shadow(color: BVColor.shadowStrong, radius: 30, x: 0, y: 24)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Standalone "Connect" button. Tapping kicks off the onboarding agent
    /// flow for the currently selected agent (shown in the pill below).
    private var connectButton: some View {
        Button(action: { onConnect?(selectedAgent) }) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.72)
                }
                Text(String(localized: "email.connect.button.connect", defaultValue: "Connect"))
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(BVColor.bgHover)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(BVColor.border))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLoading || onConnect == nil || !selectedAgent.isAvailable)
    }

    /// Nested agent pill (darker fill capsule) inside `connectAndAgentBox`.
    /// Tapping opens the agent dropdown.
    private var agentSelectorButton: some View {
        Button {
            agentMenuOpen.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: selectedAgent.symbolName)
                    .font(.system(size: 11, weight: .medium))
                Text(selectedAgent.label)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(BVColor.fgFaint)
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(
                Capsule()
                    .fill(BVColor.bg)
                    .overlay(Capsule().stroke(BVColor.border.opacity(0.6)))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // Publish the button's bounds so `disconnectedContent` can render the
        // dropdown BELOW the pill via `.overlayPreferenceValue`. Embedding the
        // dropdown inline as an `.overlay` on this Button was unreliable —
        // alignmentGuide offsets didn't escape some intermediate layout
        // boundary and the popup rendered above the trigger instead of below.
        .anchorPreference(key: EmailAgentButtonAnchorKey.self, value: .bounds) { $0 }
    }

    private func errorContent(_ message: String) -> some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22))
                .foregroundColor(BVColor.fgFaint)
            Text(String(localized: "email.error.load", defaultValue: "Gmail을 불러오지 못했습니다"))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(BVColor.fgMute)
            Text(message)
                .font(.system(size: 11))
                .foregroundColor(BVColor.fgFaint)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .padding(.horizontal, 24)
            if !isConnected {
                Button(action: { onConnect?(selectedAgent) }) {
                    HStack(spacing: 6) {
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.72)
                        } else {
                            Image(systemName: "link")
                                .font(.system(size: 11, weight: .medium))
                        }
                        Text(String(localized: "email.connect.button", defaultValue: "Gmail 연결"))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(BVColor.bgHover)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(BVColor.border))
                    )
                }
                .buttonStyle(.plain)
                .disabled(isLoading || onConnect == nil)
            }
            Button(action: { onRefresh?() }) {
                HStack(spacing: 6) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.72)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .medium))
                    }
                    Text(String(localized: "email.error.retry", defaultValue: "다시 시도"))
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(BVColor.bgHover)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(BVColor.border))
                )
            }
            .buttonStyle(.plain)
            .disabled(isLoading || onRefresh == nil)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BVColor.bg)
    }

    private func repairContent(_ state: ZebraEmailConnectionRepairState) -> some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            if state.kind == .provisioning {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.86)
                    .frame(height: 24)
            } else {
                Image(systemName: repairSymbol(for: state.kind))
                    .font(.system(size: 22))
                    .foregroundColor(BVColor.fgFaint)
            }
            Text(repairTitle(for: state.kind))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(BVColor.fgMute)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 18)
            Text(repairSubtitle(for: state))
                .font(.system(size: 11))
                .foregroundColor(BVColor.fgFaint)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .padding(.horizontal, 22)
            if let detail = state.detail, state.kind == .provisioningFailed || state.kind == .authorizationFailed {
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundColor(BVColor.fgFaint.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 24)
            }
            if state.kind != .provisioning {
                Button(action: { onConnect?(selectedAgent) }) {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                            .font(.system(size: 11, weight: .medium))
                        Text(String(localized: "email.repair.button.reconnect", defaultValue: "Gmail 재연결"))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(BVColor.bgHover)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(BVColor.border))
                    )
                }
                .buttonStyle(.plain)
                .disabled(isLoading || onConnect == nil || !selectedAgent.isAvailable)
                agentSelectorButton
            }
            Button(action: { onRefresh?() }) {
                HStack(spacing: 6) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.72)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .medium))
                    }
                    Text(String(localized: "email.error.retry", defaultValue: "다시 시도"))
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(BVColor.bgHover)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(BVColor.border))
                )
            }
            .buttonStyle(.plain)
            .disabled(isLoading || onRefresh == nil)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BVColor.bg)
        .overlayPreferenceValue(EmailAgentButtonAnchorKey.self) { anchor in
            agentDropdownOverlay(anchor: anchor)
        }
    }

    private func repairSymbol(for kind: ZebraEmailConnectionRepairState.Kind) -> String {
        switch kind {
        case .configurationMissing:
            return "envelope.badge"
        case .taskExpired, .taskUnavailable, .authorizationFailed, .provisioningFailed:
            return "exclamationmark.triangle"
        case .taskPendingApproval:
            return "checkmark.shield"
        case .provisioning:
            return "link.badge.plus"
        }
    }

    private func repairTitle(for kind: ZebraEmailConnectionRepairState.Kind) -> String {
        switch kind {
        case .configurationMissing:
            return String(localized: "email.repair.configurationMissing.title", defaultValue: "Gmail 연결 필요")
        case .taskExpired:
            return String(localized: "email.repair.taskExpired.title", defaultValue: "Gmail 연결이 만료됐습니다")
        case .taskPendingApproval:
            return String(localized: "email.repair.taskPendingApproval.title", defaultValue: "Clawvisor 승인이 필요합니다")
        case .authorizationFailed:
            return String(localized: "email.repair.authorizationFailed.title", defaultValue: "Clawvisor 인증이 필요합니다")
        case .taskUnavailable:
            return String(localized: "email.repair.taskUnavailable.title", defaultValue: "Gmail 연결을 다시 확인해야 합니다")
        case .provisioning:
            return String(localized: "email.repair.provisioning.title", defaultValue: "새 Gmail 권한을 요청하는 중")
        case .provisioningFailed:
            return String(localized: "email.repair.provisioningFailed.title", defaultValue: "자동 복구를 완료하지 못했습니다")
        }
    }

    private func repairSubtitle(for state: ZebraEmailConnectionRepairState) -> String {
        switch state.kind {
        case .configurationMissing:
            return String(localized: "email.repair.configurationMissing.subtitle", defaultValue: "Clawvisor 설정을 완료하면 받은편지함 동기화가 다시 시작됩니다.")
        case .taskExpired:
            return String(localized: "email.repair.taskExpired.subtitle", defaultValue: "기존 Gmail 권한이 만료되었습니다. 새 standing task 승인이 필요합니다.")
        case .taskPendingApproval:
            return String(localized: "email.repair.taskPendingApproval.subtitle", defaultValue: "Clawvisor 대시보드에서 새 Gmail task를 승인한 뒤 다시 시도하세요.")
        case .authorizationFailed:
            return String(localized: "email.repair.authorizationFailed.subtitle", defaultValue: "Clawvisor agent token 또는 Gmail 권한을 다시 연결해야 합니다.")
        case .taskUnavailable:
            return String(localized: "email.repair.taskUnavailable.subtitle", defaultValue: "저장된 Gmail task를 더 이상 사용할 수 없습니다. 다시 연결해 주세요.")
        case .provisioning:
            return String(localized: "email.repair.provisioning.subtitle", defaultValue: "Zebra가 만료되지 않는 Gmail task를 만들고 있습니다.")
        case .provisioningFailed:
            return String(localized: "email.repair.provisioningFailed.subtitle", defaultValue: "Claude Code onboarding으로 다시 연결하거나 잠시 후 다시 시도하세요.")
        }
    }
}
