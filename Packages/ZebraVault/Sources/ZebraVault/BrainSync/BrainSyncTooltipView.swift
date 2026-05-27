import SwiftUI

/// `BrainSyncIndicatorView` 가 hover 시 띄우는 popover 내용. 디자인 spec
/// (`/Users/han/zebra_design/zebra_sync/`) 의 `.ss-tip` 컴포넌트.
///
/// 3 분기:
/// - synced: row "[Last synced] [3m ago]" + passive status hint
/// - failed (reason ≠ conflict): row "[{한글 reason}] [14m ago]" + detail + passive next-step hint
/// - failed (reason = conflict): row "[동기화 충돌] [7m ago]" + detail + conflict CTA
///
/// Conflict 의 agent picker chip 자체는 단계 3 에서 별도 view (`BrainSyncAgentPicker`).
/// 단계 2 에선 hint 자리에 passive 안내 텍스트만 표시.
struct BrainSyncTooltipView: View {
    @ObservedObject var service: BrainSyncService
    /// Conflict reason 일 때 agent 선택 callback. nil 이면 picker 안 보이고
    /// 그냥 generic hint 만 표시 (= 단계 3 의존성 없을 때의 fallback).
    var onConflictAgentSelect: ((MarkdownPillAgent) -> Void)?

    @State private var preferredAgent: MarkdownPillAgent = BrainSyncAgentPreference.current

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            statusRow
            if let detail = failureDetail {
                detailRow(detail)
            }
            if isConflict, onConflictAgentSelect != nil {
                conflictPicker
            } else {
                hintRow
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        // 디자인 spec line 154: detail row max-width 240, white-space normal.
        // width 고정 240 → 내부 Text 자동 wrap. height 는 content.
        .frame(width: 240, alignment: .center)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: NSColor(srgbRed: 0x0a / 255.0, green: 0x0a / 255.0, blue: 0x0a / 255.0, alpha: 1.0)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(BVColor.borderStrong, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 8)
        .accessibilityIdentifier("BrainSyncTooltip")
    }

    // MARK: - Rows

    @ViewBuilder
    private var statusRow: some View {
        HStack(spacing: 14) {
            Text(reasonLabel)
                .font(.system(size: 11.5, weight: reasonWeight))
                .foregroundColor(reasonColor)
            Text(timestampLabel)
                .font(.system(size: 11.5))
                .monospacedDigit()
                .foregroundColor(BVColor.fg)
        }
    }

    private func detailRow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundColor(BVColor.fgMute)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 240)
            .padding(.top, 2)
    }

    /// Passive hint row. Only the conflict picker below owns an explicit
    /// action; generic failure hints describe the next step but do not pretend
    /// to open logs, auth flows, or repo pickers that do not exist yet.
    @ViewBuilder
    private var hintRow: some View {
        Divider()
            .background(BVColor.border)
            .padding(.top, 6)
        Text(hintText)
            .font(.system(size: 10.5))
            .foregroundColor(BVColor.fgFaint)
            .multilineTextAlignment(.center)
            .padding(.top, 6)
    }

    /// conflict reason 일 때 hint 자리에 표시되는 agent picker (chip + dropdown).
    /// `onConflictAgentSelect` 가 nil 이면 안 그림 (= 호출자가 단계 3-b 의 terminal
    /// flow 를 아직 wire-up 안 한 케이스).
    @ViewBuilder
    private var conflictPicker: some View {
        Divider()
            .background(BVColor.border)
            .padding(.top, 6)
        BrainSyncAgentPicker(
            preferredAgent: $preferredAgent,
            onSelect: { agent in
                BrainSyncAgentPreference.set(agent)
                onConflictAgentSelect?(agent)
            }
        )
    }

    private var isConflict: Bool {
        if case .failed(_, .conflict, _)? = service.state { return true }
        return false
    }

    // MARK: - Content derivation

    private var reasonLabel: String {
        switch service.state {
        case .synced?:
            return String(localized: "brainSync.tooltip.lastSynced", defaultValue: "Last synced")
        case .failed(_, let reason, _)?:
            return reason.humanLabel
        case nil:
            return String(localized: "brainSync.tooltip.pending", defaultValue: "Sync pending")
        }
    }

    private var reasonWeight: Font.Weight {
        switch service.state {
        case .failed?:
            return .medium
        default:
            return .regular
        }
    }

    private var reasonColor: Color {
        switch service.state {
        case .failed?:
            return BVColor.syncRedLabel
        default:
            return BVColor.fgFaint
        }
    }

    private var failureDetail: String? {
        if case let .failed(_, _, detail)? = service.state, !detail.isEmpty {
            return detail
        }
        return nil
    }

    private var hintText: String {
        switch service.state {
        case .synced?:
            return String(localized: "brainSync.hint.synced", defaultValue: "sync is up to date")
        case .failed(_, let reason, _)?:
            return reason.hintText
        case nil:
            return String(localized: "brainSync.hint.pending", defaultValue: "waiting for first sync")
        }
    }

    private var timestampLabel: String {
        let date: Date?
        switch service.state {
        case .synced(let at, _)?: date = at
        case .failed(let at, _, _)?: date = at
        case nil: date = nil
        }
        guard let date else { return "—" }
        return Self.format(timeAgo: date)
    }

    /// `Xm ago` / `Xh ago` / `yesterday` / absolute date. 디자인 spec 에 따른
    /// compact format. tabular-num 은 SwiftUI 의 `monospacedDigit()` 으로.
    static func format(timeAgo date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 {
            return String(localized: "brainSync.time.justNow", defaultValue: "just now")
        }
        let minutes = Int(seconds / 60)
        if minutes < 60 {
            return String(format: "%dm ago", minutes)
        }
        let hours = Int(seconds / 3600)
        if hours < 24 {
            return String(format: "%dh ago", hours)
        }
        let days = Int(seconds / 86_400)
        if days < 2 {
            return String(localized: "brainSync.time.yesterday", defaultValue: "yesterday")
        }
        if days < 7 {
            return String(format: "%dd ago", days)
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

extension BrainSyncService.FailureReason {
    /// Tooltip's passive next-step hint.
    var hintText: String {
        switch self {
        case .authExpired:
            return String(localized: "brainSync.hint.reauth", defaultValue: "reauthenticate, then retry")
        case .offline:
            return String(localized: "brainSync.hint.offline", defaultValue: "queued · retry in 30s")
        case .pushRejected:
            return String(localized: "brainSync.hint.pullAndRetry", defaultValue: "pull remote changes, then retry")
        case .permissionDenied:
            return String(localized: "brainSync.hint.requestAccess", defaultValue: "check repository access")
        case .diskFull:
            return String(localized: "brainSync.hint.diskUsage", defaultValue: "free disk space, then retry")
        case .hookFailed:
            return String(localized: "brainSync.hint.viewLog", defaultValue: "check the sync log")
        case .rateLimit:
            return String(localized: "brainSync.hint.rateLimit", defaultValue: "rate limited · auto retry")
        case .conflict:
            return String(localized: "brainSync.hint.resolve", defaultValue: "resolve with an agent in terminal")
        case .notGbrainRepo:
            return String(localized: "brainSync.hint.chooseGbrainRepo", defaultValue: "choose a GBrain repo")
        case .alreadyRunning:
            return String(localized: "brainSync.hint.alreadyRunning", defaultValue: "wait for the current sync, then retry")
        case .unknown:
            return String(localized: "brainSync.hint.retry", defaultValue: "retry from the sync indicator")
        }
    }
}
