import SwiftUI

public struct BrainSaveStatusIndicatorView: View {
    @ObservedObject public var service: BrainSaveStatusService
    public var onFailureAgentSelect: ((MarkdownPillAgent, Date?, BrainSaveFailure) -> Void)?

    public init(
        service: BrainSaveStatusService,
        onFailureAgentSelect: ((MarkdownPillAgent, Date?, BrainSaveFailure) -> Void)? = nil
    ) {
        self.service = service
        self.onFailureAgentSelect = onFailureAgentSelect
    }

    public var body: some View {
        BrainStatusPillChrome(
            label: label,
            isSpinning: isSaving || service.isRefreshing,
            dotColor: dotColor,
            labelColor: labelColor,
            isDisabled: isSaving || service.isRefreshing,
            accessibilityIdentifier: "BrainSaveStatusIndicator",
            action: {
                ZebraTelemetry.trackSidebarInteraction(
                    area: .statusButton,
                    surface: .sync,
                    action: .click,
                    value: telemetryStatus
                )
                service.refresh()
            }
        ) {
            BrainSaveStatusTooltipView(
                snapshot: service.snapshot,
                onFailureAgentSelect: onFailureAgentSelect
            )
        }
    }

    private var label: String {
        if service.isRefreshing, !isSaving {
            return String(localized: "brainSave.label.checking", defaultValue: "Checking…")
        }
        switch service.snapshot.status {
        case .saved:
            return String(localized: "brainSave.label.saved", defaultValue: "Saved")
        case .saving:
            return String(localized: "brainSave.label.saving", defaultValue: "Saving…")
        case .failed:
            return String(localized: "brainSave.label.failed", defaultValue: "Save failed")
        case .unknown:
            return String(localized: "brainSave.label.pending", defaultValue: "Save pending")
        }
    }

    private var isSaving: Bool {
        if case .saving = service.snapshot.status { return true }
        return false
    }

    private var dotColor: Color {
        switch service.snapshot.status {
        case .saved:
            return BVColor.syncGreen
        case .failed:
            return BVColor.syncRed
        case .saving:
            return BVColor.syncAmber
        case .unknown:
            return BVColor.fgFaint
        }
    }

    private var labelColor: Color {
        switch service.snapshot.status {
        case .failed:
            return BVColor.syncRedLabel
        default:
            return BVColor.fg
        }
    }

    private var telemetryStatus: String {
        if service.isRefreshing { return "syncing" }
        switch service.snapshot.status {
        case .saved:
            return "saved"
        case .saving:
            return "syncing"
        case .failed:
            return "error"
        case .unknown:
            return "unknown"
        }
    }

}

private struct BrainSaveStatusTooltipView: View {
    let snapshot: BrainSaveStatusSnapshot
    var onFailureAgentSelect: ((MarkdownPillAgent, Date?, BrainSaveFailure) -> Void)?

    @State private var now = Date()
    @State private var ticker: Timer?

    var body: some View {
        BrainStatusTooltipChrome(accessibilityIdentifier: "BrainSaveStatusTooltip") {
            VStack(alignment: .center, spacing: 0) {
                header
                if let failedState {
                    Divider()
                        .background(BVColor.border)
                        .padding(.vertical, 6)
                    BrainStatusResolveButton(
                        action: {
                            onFailureAgentSelect?(MarkdownPillAgent.defaultAgent(), failedState.at, failedState.failure)
                        },
                        isDisabled: onFailureAgentSelect == nil
                    )
                }
            }
        }
        .onAppear(perform: startTicker)
        .onDisappear(perform: stopTicker)
    }

    private var header: some View {
        VStack(alignment: .center, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title)
                    .font(.system(size: 11.5, weight: titleWeight))
                    .foregroundColor(titleColor)
                    .lineLimit(1)
                Text(timestampLabel)
                    .font(.system(size: 11.5))
                    .monospacedDigit()
                    .foregroundColor(BrainSaveStatusPopoverPalette.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Text(detail)
                .font(.system(size: 10.5))
                .foregroundColor(BrainSaveStatusPopoverPalette.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var title: String {
        switch snapshot.status {
        case .saved:
            return String(localized: "brainSave.label.saved", defaultValue: "Saved")
        case .saving:
            return String(localized: "brainSave.label.saving", defaultValue: "Saving…")
        case .failed:
            return String(localized: "brainSave.label.failed", defaultValue: "Save failed")
        case .unknown:
            return String(localized: "brainSave.label.pending", defaultValue: "Save pending")
        }
    }

    private var titleColor: Color {
        if case .failed = snapshot.status {
            return BrainSaveStatusPopoverPalette.failureTitle
        }
        return BrainSaveStatusPopoverPalette.primaryText
    }

    private var titleWeight: Font.Weight {
        if case .failed = snapshot.status { return .medium }
        return .regular
    }

    private var detail: String {
        switch snapshot.status {
        case .saved:
            return runtimeDetail(defaultText: String(localized: "brainSave.detail.saved", defaultValue: "GBrain save status is current"))
        case .saving:
            return runtimeDetail(defaultText: String(localized: "brainSave.detail.saving", defaultValue: "GBrain save work is running"))
        case .failed(_, let failure):
            return failure.message
        case .unknown:
            return runtimeDetail(defaultText: String(localized: "brainSave.detail.pending", defaultValue: "No completed GBrain save has been detected yet"))
        }
    }

    private var failedState: (at: Date?, failure: BrainSaveFailure)? {
        if case let .failed(at, failure) = snapshot.status {
            return (at, failure)
        }
        return nil
    }

    private func runtimeDetail(defaultText: String) -> String {
        guard let runtime = snapshot.runtime else { return defaultText }
        let prefix: String
        switch runtime {
        case .gbrain:
            prefix = String(localized: "brainSave.runtime.gbrain", defaultValue: "GBrain")
        case .openClaw:
            prefix = String(localized: "brainSave.runtime.openClaw", defaultValue: "OpenClaw")
        case .hermes:
            prefix = String(localized: "brainSave.runtime.hermes", defaultValue: "Hermes")
        }
        if let detail = snapshot.detail, !detail.isEmpty {
            return "\(prefix): \(detail)"
        }
        return "\(prefix): \(defaultText)"
    }

    private var timestampLabel: String {
        let date: Date?
        switch snapshot.status {
        case .saved(let at): date = at
        case .saving(let startedAt): date = startedAt
        case .failed(let at, _): date = at
        case .unknown: date = nil
        }
        guard let date else { return "--" }
        return BrainStatusRelativeTimeFormatter.format(timeAgo: date, now: now, style: .brainSave)
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
}

private enum BrainSaveStatusPopoverPalette {
    static let primaryText = BVColor.fg
    static let secondaryText = BVColor.fgMute
    static let failureTitle = BVColor.syncRedLabel
}
