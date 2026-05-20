import SwiftUI

public struct VerticalTabsSidebarEmailContent: View {
    @ObservedObject public var state: VerticalTabsSidebarModeState
    private let threads: [EmailThreadItem]?
    private let userLabels: [EmailUserLabel]?
    private let isConnected: Bool
    private let isLoading: Bool
    private let isSyncing: Bool
    private let errorMessage: String?
    private let selectedThreadId: String?
    private let onConnect: (() -> Void)?
    private let onRefresh: (() -> Void)?
    private let onSelectThread: ((EmailThreadItem) -> Void)?
    private let onCreateLabel: ((String) -> EmailUserLabel)?

    public init(state: VerticalTabsSidebarModeState) {
        self.state = state
        self.threads = nil
        self.userLabels = nil
        self.isConnected = true
        self.isLoading = false
        self.isSyncing = false
        self.errorMessage = nil
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
        selectedThreadId: String?,
        onConnect: @escaping () -> Void,
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
        if let errorMessage, !errorMessage.isEmpty, resolvedThreads.isEmpty {
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
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            Image(systemName: "envelope.badge")
                .font(.system(size: 22))
                .foregroundColor(BVColor.fgFaint)
            Text(String(localized: "email.connect.prompt", defaultValue: "Gmail을 연결하면 받은편지함 목록이 표시됩니다"))
                .font(.system(size: 12))
                .foregroundColor(BVColor.fgMute)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button(action: { onConnect?() }) {
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
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BVColor.bg)
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
                Button(action: { onConnect?() }) {
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
}
