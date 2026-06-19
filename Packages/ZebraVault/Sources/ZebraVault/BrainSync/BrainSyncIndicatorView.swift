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
/// 클릭 = synced/pending 일 때 즉시 `BrainSyncService.triggerSync()` 호출.
/// failed 상태의 복구/재시도 action 은 popover 안의 case-aware 버튼이 소유한다.
public struct BrainSyncIndicatorView: View {
    @ObservedObject public var service: BrainSyncService
    /// Action-required failure 에서 Resolve with AI 를 누르면 호출.
    /// Brain sync 는 별도 agent picker 를 갖지 않고 primary agent 를 사용한다.
    /// cmux app module 의 caller 가 terminal split + agent CLI 실행을 wire up.
    public var onFailureAgentSelect: ((MarkdownPillAgent, Date, BrainSyncService.Failure) -> Void)?

    public init(
        service: BrainSyncService,
        onFailureAgentSelect: ((MarkdownPillAgent, Date, BrainSyncService.Failure) -> Void)? = nil
    ) {
        self.service = service
        self.onFailureAgentSelect = onFailureAgentSelect
    }

    public var body: some View {
        BrainStatusPillChrome(
            label: label,
            isSpinning: service.isSyncing,
            dotColor: dotColor,
            labelColor: labelColor,
            isDisabled: service.isSyncing,
            accessibilityIdentifier: "BrainSyncIndicator",
            action: handleClick
        ) {
            BrainSyncTooltipView(
                service: service,
                onFailureAgentSelect: onFailureAgentSelect
            )
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
        guard !service.isSyncing else { return }
        if case .failed? = service.state { return }
        service.triggerSync()
    }
}
