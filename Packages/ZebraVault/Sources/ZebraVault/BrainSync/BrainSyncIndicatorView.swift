import SwiftUI

/// Sidebar footer 의 brain sync indicator. 7×7 dot + label.
///
/// 디자인 (`/Users/han/zebra_design/zebra_sync/`) 의 `SyncEl` 컴포넌트 spec 대로:
/// - synced: dot green / label "Synced" / `BVColor.fg`
/// - failed (모든 reason, conflict 포함): dot red / label "Sync failed" / `BVColor.syncRedLabel`
/// - syncing (transient, in-flight): dot amber + 회전 glyph / label "Syncing…" / `BVColor.fg`
///
/// Conflict 케이스의 시각 차이는 **dot/label 색이 아니라 tooltip 내용** (별도 view).
///
/// 클릭 = 즉시 `BrainSyncService.triggerSync()` 호출 (= 사용자 수동 retry).
/// in-flight 중에는 disabled — 서비스 자체가 idempotent 라 안전망까지 둠.
public struct BrainSyncIndicatorView: View {
    @ObservedObject public var service: BrainSyncService
    /// Failure reason 일 때 picker 에서 agent 선택 / indicator click 시 호출.
    /// nil 이면 generic retry 로 fall back. cmux app module 의 caller 가 terminal
    /// split + agent CLI 실행을 wire up.
    public var onFailureAgentSelect: ((MarkdownPillAgent, Date, BrainSyncService.Failure) -> Void)?

    // Two hover detectors so that the tooltip area itself can keep the
    // popover open. SwiftUI's `.onHover` only fires within a view's layout
    // frame; the tooltip is `.offset`-ed above the indicator so its frame
    // stays in the indicator's row. Without a second detector on the tooltip
    // itself, the moment the mouse leaves the indicator's row the hover
    // goes false and the popover vanishes — exactly the bug the user hit.
    @State private var buttonHovering = false
    @State private var tooltipHovering = false
    private var hovering: Bool { buttonHovering || tooltipHovering }

    public init(
        service: BrainSyncService,
        onFailureAgentSelect: ((MarkdownPillAgent, Date, BrainSyncService.Failure) -> Void)? = nil
    ) {
        self.service = service
        self.onFailureAgentSelect = onFailureAgentSelect
    }

    public var body: some View {
        Button(action: handleClick) {
            HStack(spacing: 6) {
                dot
                Text(label)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(labelColor)
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(hovering ? BVColor.bgHover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(service.isSyncing)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .fixedSize(horizontal: true, vertical: false)
        .onHover { buttonHovering = $0 }
        // Tooltip overlay — button padding-top(5) + button(24) + padding-bottom(5)
        // = 34pt 구조. 디자인 spec: tooltip bottom 이 button top 위 10pt 에 정렬.
        // View bottom 으로부터 위로 (padding-bottom 5 + button 24 + gap 10) = 39pt.
        .overlay(alignment: .bottomTrailing) {
            if hovering {
                BrainSyncTooltipView(
                    service: service,
                    onFailureAgentSelect: onFailureAgentSelect
                )
                    .offset(y: -39)
                    .onHover { tooltipHovering = $0 }
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityIdentifier("BrainSyncIndicator")
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var dot: some View {
        if service.isSyncing {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(BVColor.syncAmber)
                .rotationEffect(.degrees(spinAngle))
                .onAppear { startSpin() }
                .onDisappear { stopSpin() }
        } else {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
        }
    }

    private var label: String {
        if service.isSyncing {
            return String(localized: "brainSync.label.syncing", defaultValue: "Syncing…")
        }
        switch service.state {
        case .synced?:
            return String(localized: "brainSync.label.synced", defaultValue: "Synced")
        case .failed?:
            return String(localized: "brainSync.label.failed", defaultValue: "Sync failed")
        case nil:
            return String(localized: "brainSync.label.idle", defaultValue: "Sync pending")
        }
    }

    private var dotColor: Color {
        switch service.state {
        case .synced?:
            return BVColor.syncGreen
        case .failed?:
            return BVColor.syncRed
        case nil:
            return BVColor.fgFaint
        }
    }

    private var labelColor: Color {
        switch service.state {
        case .failed?:
            return BVColor.syncRedLabel
        default:
            return BVColor.fg
        }
    }

    private func handleClick() {
        #if DEBUG
        NSLog("[BrainSync] indicator clicked. isSyncing=\(service.isSyncing) state=\(String(describing: service.state))")
        #endif
        // Failure reason 일 때 click = default agent (UserDefaults 의 preferred,
        // 첫 사용 시 codex) 로 즉시 agent terminal. synced/pending 일 때는 sync retry.
        if case let .failed(failedAt, failure)? = service.state, let onFailureAgentSelect {
            onFailureAgentSelect(BrainSyncAgentPreference.current, failedAt, failure)
            return
        }
        guard !service.isSyncing else { return }
        service.triggerSync()
    }

    // MARK: - Spin animation

    @State private var spinAngle: Double = 0
    @State private var spinTimer: Timer?

    private func startSpin() {
        stopSpin()
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            DispatchQueue.main.async {
                spinAngle = (spinAngle + 12).truncatingRemainder(dividingBy: 360)
            }
        }
        RunLoop.current.add(timer, forMode: .common)
        spinTimer = timer
    }

    private func stopSpin() {
        spinTimer?.invalidate()
        spinTimer = nil
    }
}
