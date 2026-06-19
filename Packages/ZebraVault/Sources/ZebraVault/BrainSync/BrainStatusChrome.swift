import SwiftUI

struct BrainStatusPillChrome<Tooltip: View>: View {
    let label: String
    let isSpinning: Bool
    let dotColor: Color
    let labelColor: Color
    let isDisabled: Bool
    let accessibilityIdentifier: String
    let action: () -> Void
    let tooltip: () -> Tooltip

    @State private var buttonHovering = false
    @State private var tooltipHovering = false
    @State private var spinAngle: Double = 0
    @State private var spinTimer: Timer?

    private var hovering: Bool { buttonHovering || tooltipHovering }

    var body: some View {
        Button(action: action) {
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
        .disabled(isDisabled)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .fixedSize(horizontal: true, vertical: false)
        .onHover { buttonHovering = $0 }
        .overlay(alignment: .bottomTrailing) {
            if hovering {
                tooltip()
                    .offset(y: -39)
                    .onHover { tooltipHovering = $0 }
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var dot: some View {
        if isSpinning {
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

struct BrainStatusTooltipChrome<Content: View>: View {
    let accessibilityIdentifier: String
    let content: () -> Content

    private let popoverWidth: CGFloat = 240
    private let cornerRadius: CGFloat = 6

    var body: some View {
        content()
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(width: popoverWidth, alignment: .center)
            .fixedSize(horizontal: false, vertical: true)
            .background(popoverBackground)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(BVColor.borderStrong, lineWidth: 1)
            )
            .shadow(color: BVColor.shadow, radius: 12, x: 0, y: 8)
            .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var popoverBackground: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(BVColor.bgFloating)
            )
    }
}

struct BrainStatusResolveButton: View {
    let action: () -> Void
    let isDisabled: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(BVColor.accent)
                Text(String(localized: "brainStatus.action.resolveWithAI", defaultValue: "Resolve with AI"))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(BrainStatusResolvePillButtonStyle())
        .disabled(isDisabled)
    }
}

struct BrainStatusResolvePillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundColor(BVColor.fg)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(
                Capsule()
                    .fill(configuration.isPressed ? BVColor.bgHover : Color.clear)
            )
            .overlay(
                Capsule()
                    .stroke(BVColor.borderStrong, lineWidth: 1)
            )
            .contentShape(Capsule())
            .offset(y: configuration.isPressed ? 0.5 : 0)
    }
}

enum BrainStatusRelativeTimeStyle {
    case brainSync
    case brainSave
}

enum BrainStatusRelativeTimeFormatter {
    static func format(timeAgo date: Date, now: Date = Date(), style: BrainStatusRelativeTimeStyle) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 {
            switch style {
            case .brainSync:
                return String(localized: "brainSync.time.justNow", defaultValue: "just now")
            case .brainSave:
                return String(localized: "brainSave.time.justNow", defaultValue: "just now")
            }
        }
        let minutes = Int(seconds / 60)
        if minutes < 60 {
            switch style {
            case .brainSync:
                return String(format: String(localized: "brainSync.time.minutesAgo", defaultValue: "%dm ago"), minutes)
            case .brainSave:
                return String(format: String(localized: "brainSave.time.minutesAgo", defaultValue: "%dm ago"), minutes)
            }
        }
        let hours = Int(seconds / 3600)
        if hours < 24 {
            switch style {
            case .brainSync:
                return String(format: String(localized: "brainSync.time.hoursAgo", defaultValue: "%dh ago"), hours)
            case .brainSave:
                return String(format: String(localized: "brainSave.time.hoursAgo", defaultValue: "%dh ago"), hours)
            }
        }
        let days = Int(seconds / 86_400)
        if days < 2 {
            switch style {
            case .brainSync:
                return String(localized: "brainSync.time.yesterday", defaultValue: "yesterday")
            case .brainSave:
                return String(localized: "brainSave.time.yesterday", defaultValue: "yesterday")
            }
        }
        if days < 7 {
            switch style {
            case .brainSync:
                return String(format: String(localized: "brainSync.time.daysAgo", defaultValue: "%dd ago"), days)
            case .brainSave:
                return String(format: String(localized: "brainSave.time.daysAgo", defaultValue: "%dd ago"), days)
            }
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
