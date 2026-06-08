import SwiftUI

/// Brain sync status popover. The action region is case-aware:
/// retryable failures show the automatic retry timer plus "지금 동기화";
/// action-required failures show only "Resolve with AI".
struct BrainSyncTooltipView: View {
    @ObservedObject var service: BrainSyncService
    var onFailureAgentSelect: ((MarkdownPillAgent, Date, BrainSyncService.Failure) -> Void)?

    private static let popoverWidth: CGFloat = 240
    private static let cornerRadius: CGFloat = 6

    @State private var now = Date()
    @State private var ticker: Timer?

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            header
            Divider()
                .background(BrainSyncResolvePopoverPalette.divider)
                .padding(.vertical, 6)
            actionRegion
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: Self.popoverWidth, alignment: .center)
        .fixedSize(horizontal: false, vertical: true)
        .background(popoverBackground)
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .stroke(BVColor.borderStrong, lineWidth: 1)
        )
        .shadow(color: BVColor.shadow, radius: 12, x: 0, y: 8)
        .accessibilityIdentifier("BrainSyncTooltip")
        .onAppear(perform: startTicker)
        .onDisappear(perform: stopTicker)
    }

    private var popoverBackground: some View {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .fill(BVColor.bgFloating)
            )
    }

    private var header: some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(titleText)
                    .font(.system(size: 11.5, weight: titleWeight))
                    .foregroundColor(titleColor)
                    .lineLimit(1)
                Text(timestampLabel)
                    .font(.system(size: 11.5))
                    .monospacedDigit()
                    .foregroundColor(BrainSyncResolvePopoverPalette.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Text(detailText)
                .font(.system(size: 10.5))
                .foregroundColor(BrainSyncResolvePopoverPalette.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    @ViewBuilder
    private var actionRegion: some View {
        if let failedState {
            if failedState.failure.reason.allowsAutomaticRetry {
                autoRetryRegion
            } else {
                resolveRegion(failedState)
            }
        } else {
            syncNowButton
        }
    }

    private var autoRetryRegion: some View {
        VStack(spacing: 8) {
            VStack(spacing: 6) {
                HStack(alignment: .center, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.system(size: 11, weight: .medium))
                        Text(String(localized: "brainSync.retry.timerLabel", defaultValue: "자동 동기화까지"))
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .foregroundColor(BrainSyncResolvePopoverPalette.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(countdownLabel)
                        .font(.system(size: 11.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundColor(BrainSyncResolvePopoverPalette.primaryText)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(BrainSyncResolvePopoverPalette.progressTrack)
                        Capsule()
                            .fill(BrainSyncResolvePopoverPalette.accent)
                            .frame(width: proxy.size.width * progressFraction)
                    }
                }
                .frame(height: 5)
            }

            syncNowButton
        }
    }

    private func resolveRegion(_ failedState: (at: Date, failure: BrainSyncService.Failure)) -> some View {
        Button(action: {
            onFailureAgentSelect?(MarkdownPillAgent.defaultAgent(), failedState.at, failedState.failure)
        }) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(BrainSyncResolvePopoverPalette.accent)
                Text(String(localized: "brainSync.action.resolveWithAI", defaultValue: "Resolve with AI"))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(BrainSyncResolvePillButtonStyle())
        .disabled(onFailureAgentSelect == nil)
    }

    private var syncNowButton: some View {
        Button(action: { service.triggerSync() }) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11.5, weight: .medium))
                    .opacity(0.65)
                Text(syncNowTitle)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(BrainSyncResolvePillButtonStyle())
        .disabled(service.isSyncing)
    }

    private var syncNowTitle: String {
        if service.isSyncing {
            return String(localized: "brainSync.action.syncingNow", defaultValue: "동기화 중...")
        }
        return String(localized: "brainSync.action.syncNow", defaultValue: "지금 동기화")
    }

    private var failedState: (at: Date, failure: BrainSyncService.Failure)? {
        if case let .failed(at, failure)? = service.state {
            return (at, failure)
        }
        return nil
    }

    private var titleText: String {
        guard let failedState else {
            if service.isSyncing {
                return String(localized: "brainSync.label.syncing", defaultValue: "Syncing...")
            }
            return String(localized: "brainSync.label.synced", defaultValue: "Synced")
        }
        if failedState.failure.reason.allowsAutomaticRetry {
            return String(localized: "brainSync.popover.autoTitle", defaultValue: "동기화 실패")
        }
        return failedState.failure.reason.humanLabel
    }

    private var titleColor: Color {
        failedState == nil
            ? BrainSyncResolvePopoverPalette.primaryText
            : BrainSyncResolvePopoverPalette.failureTitle
    }

    private var titleWeight: Font.Weight {
        failedState == nil ? .regular : .medium
    }

    private var detailText: String {
        guard let failedState else {
            if service.isSyncing {
                return String(localized: "brainSync.popover.syncingDetail", defaultValue: "동기화를 실행하고 있어요")
            }
            return String(localized: "brainSync.hint.synced", defaultValue: "sync is up to date")
        }
        return failedState.failure.shortDisplayDetail
    }

    private var timestampLabel: String {
        let date: Date?
        switch service.state {
        case .synced(let at, _)?: date = at
        case .failed(let at, _)?: date = at
        case nil: date = nil
        }
        guard let date else { return "--" }
        return Self.format(timeAgo: date, now: now)
    }

    private var countdownLabel: String {
        let remaining = max(0, (service.nextAutomaticSyncAt ?? now).timeIntervalSince(now))
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var progressFraction: CGFloat {
        guard let next = service.nextAutomaticSyncAt else { return 0 }
        let remaining = max(0, next.timeIntervalSince(now))
        let elapsed = max(0, BrainSyncService.automaticRetryInterval - remaining)
        return min(1, max(0, CGFloat(elapsed / BrainSyncService.automaticRetryInterval)))
    }

    private func startTicker() {
        stopTicker()
        now = Date()
        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            now = Date()
        }
        RunLoop.current.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    /// `Xm ago` / `Xh ago` / `yesterday` / absolute date.
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

private struct BrainSyncResolvePillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundColor(BrainSyncResolvePopoverPalette.primaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(
                Capsule()
                    .fill(configuration.isPressed ? BrainSyncResolvePopoverPalette.buttonPressed : Color.clear)
            )
            .overlay(
                Capsule()
                    .stroke(BrainSyncResolvePopoverPalette.buttonBorder, lineWidth: 1)
            )
            .contentShape(Capsule())
            .offset(y: configuration.isPressed ? 0.5 : 0)
    }
}

private enum BrainSyncResolvePopoverPalette {
    static let divider = BVColor.border
    static let failureTitle = BVColor.syncRedLabel
    static let secondaryText = BVColor.fgMute
    static let primaryText = BVColor.fg
    static let accent = BVColor.accent
    static let buttonBorder = BVColor.borderStrong
    static let buttonPressed = BVColor.bgHover
    static let progressTrack = BVColor.borderStrong
}

private extension BrainSyncService.Failure {
    var shortDisplayDetail: String {
        switch reason {
        case .offline:
            return String(localized: "brainSync.detail.offline", defaultValue: "네트워크 연결이 끊겼어요")
        case .rateLimit:
            return String(localized: "brainSync.detail.rateLimit", defaultValue: "잠시 후 다시 시도할게요")
        case .alreadyRunning:
            return String(localized: "brainSync.detail.alreadyRunning", defaultValue: "다른 동기화가 진행 중이에요")
        default:
            return Self.compact(detail)
        }
    }

    private static func compact(_ detail: String) -> String {
        let line = detail
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
        guard line.count > 72 else { return line }
        let end = line.index(line.startIndex, offsetBy: 69)
        return String(line[..<end]) + "..."
    }
}
