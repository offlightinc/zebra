import AppKit
import SwiftUI
import WebKit

public struct ZebraEmailThreadDetailView: View {
    private let subject: String
    private let detail: EmailThreadDetail?
    private let drafts: [EmailDraftSnapshot]
    private let isLoading: Bool
    private let isArchiving: Bool
    private let errorMessage: String?
    private let archiveErrorMessage: String?
    private let draftErrorMessage: String?
    private let draftErrorMessages: [String: String]
    private let expandedMessageIds: Set<String>
    /// Extra bottom padding on the scrollable thread body so a host-overlaid
    /// floating chat pill does not obscure the last message. Mirrors the
    /// pattern `ZebraMarkdownPanelView` uses (`.padding(.bottom, 160)` on the
    /// scrolled content). Defaults to 0 so non-host callers (previews, tests)
    /// render flush.
    private let bottomContentInset: CGFloat
    private let onArchive: () -> Void
    private let onDismissArchiveError: () -> Void
    private let onDismissDraftError: () -> Void
    private let onRefresh: () -> Void
    private let onToggleMessage: (String) -> Void
    private let onCreateReply: (String) -> Void
    private let onUpdateDraft: (String, Int, EmailDraftPatch) -> Void
    private let onDiscardDraft: (String) -> Void
    private let onOpenURL: (URL) -> Void

    public init(
        subject: String,
        detail: EmailThreadDetail?,
        drafts: [EmailDraftSnapshot] = [],
        isLoading: Bool,
        isArchiving: Bool = false,
        errorMessage: String?,
        archiveErrorMessage: String? = nil,
        draftErrorMessage: String? = nil,
        draftErrorMessages: [String: String] = [:],
        expandedMessageIds: Set<String>,
        bottomContentInset: CGFloat = 0,
        onArchive: @escaping () -> Void = {},
        onDismissArchiveError: @escaping () -> Void = {},
        onDismissDraftError: @escaping () -> Void = {},
        onRefresh: @escaping () -> Void,
        onToggleMessage: @escaping (String) -> Void,
        onCreateReply: @escaping (String) -> Void = { _ in },
        onUpdateDraft: @escaping (String, Int, EmailDraftPatch) -> Void = { _, _, _ in },
        onDiscardDraft: @escaping (String) -> Void = { _ in },
        onOpenURL: @escaping (URL) -> Void
    ) {
        self.subject = subject
        self.detail = detail
        self.drafts = drafts
        self.isLoading = isLoading
        self.isArchiving = isArchiving
        self.errorMessage = errorMessage
        self.archiveErrorMessage = archiveErrorMessage
        self.draftErrorMessage = draftErrorMessage
        self.draftErrorMessages = draftErrorMessages
        self.expandedMessageIds = expandedMessageIds
        self.bottomContentInset = bottomContentInset
        self.onArchive = onArchive
        self.onDismissArchiveError = onDismissArchiveError
        self.onDismissDraftError = onDismissDraftError
        self.onRefresh = onRefresh
        self.onToggleMessage = onToggleMessage
        self.onCreateReply = onCreateReply
        self.onUpdateDraft = onUpdateDraft
        self.onDiscardDraft = onDiscardDraft
        self.onOpenURL = onOpenURL
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            if let archiveErrorMessage, !archiveErrorMessage.isEmpty {
                archiveErrorBanner(archiveErrorMessage)
            }
            if let draftErrorMessage, !draftErrorMessage.isEmpty {
                draftErrorBanner(draftErrorMessage)
            }
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BVColor.bg)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "envelope")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(BVColor.fgMute)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(displaySubject)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(BVColor.fg)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(headerSubtitle)
                    .font(.system(size: 11))
                    .foregroundColor(BVColor.fgFaint)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(spacing: EmailToolbarActionMetrics.groupSpacing) {
                if detail != nil {
                    EmailHeaderIconButton(
                        systemName: "archivebox",
                        label: String(localized: "email.detail.archive", defaultValue: "Archive"),
                        isDisabled: isLoading || isArchiving,
                        isShowingProgress: isArchiving,
                        foregroundColor: BVColor.fgMute,
                        action: onArchive
                    )
                }

                if let gmailURL = EmailThreadGmailURL.build(
                    accountEmail: detail?.accountEmail,
                    providerThreadId: detail?.providerThreadId
                ) {
                    EmailHeaderIconButton(
                        systemName: "arrow.up.right.square",
                        label: String(localized: "email.detail.openInGmail", defaultValue: "Open in Gmail"),
                        foregroundColor: BVColor.fgMute,
                        action: { onOpenURL(gmailURL) }
                    )
                }

                EmailHeaderIconButton(
                    systemName: "arrow.clockwise",
                    label: String(localized: "email.detail.refresh", defaultValue: "Refresh"),
                    isDisabled: isLoading,
                    isShowingProgress: isLoading,
                    foregroundColor: BVColor.fgMute,
                    action: onRefresh
                )
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(height: 48)
        .background(BVColor.bg)
    }

    private func archiveErrorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(BVColor.fgMute)
            Text(message)
                .font(.system(size: 11))
                .foregroundColor(BVColor.fgMute)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button(action: onDismissArchiveError) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundColor(BVColor.fgFaint)
            .help(String(localized: "common.close", defaultValue: "Close"))
            .accessibilityLabel(String(localized: "common.close", defaultValue: "Close"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(BVColor.bgInput)
    }

    private func draftErrorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(BVColor.fgMute)
            Text(String.localizedStringWithFormat(
                String(localized: "email.draft.errorLine", defaultValue: "Draft error: %@"),
                message
            ))
            .font(.system(size: 11))
            .foregroundColor(BVColor.fgMute)
            .lineLimit(2)
            Spacer(minLength: 8)
            Button(action: onDismissDraftError) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundColor(BVColor.fgFaint)
            .help(String(localized: "common.close", defaultValue: "Close"))
            .accessibilityLabel(String(localized: "common.close", defaultValue: "Close"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(BVColor.bgInput)
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage, !errorMessage.isEmpty, detail == nil {
            centeredState(
                systemName: "exclamationmark.triangle",
                title: String(localized: "email.detail.error.title", defaultValue: "Couldn't load this email"),
                message: errorMessage
            )
        } else if isLoading && detail == nil {
            centeredState(
                systemName: "envelope.open",
                title: String(localized: "email.detail.loading", defaultValue: "Loading email"),
                message: nil
            )
        } else if let detail, detail.messages.isEmpty {
            centeredState(
                systemName: "tray",
                title: String(localized: "email.detail.empty", defaultValue: "No messages"),
                message: nil
            )
        } else if let detail {
            GeometryReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(detail.messages) { message in
                            EmailThreadMessageCard(
                                message: message,
                                isExpanded: expandedMessageIds.contains(message.id),
                                htmlBodyMinHeight: htmlBodyMinHeight(
                                    for: message,
                                    in: detail,
                                    viewportHeight: proxy.size.height
                                ),
                                onToggle: { onToggleMessage(message.id) },
                                onCreateReply: { onCreateReply(message.id) },
                                onOpenURL: onOpenURL
                            )
                            ForEach(draftsForMessage(message.id)) { draft in
                                EmailThreadDraftCard(
                                    draft: draft,
                                    errorMessage: draftErrorMessages[draft.localDraftId],
                                    onUpdateDraft: { baseVersion, patch in
                                        onUpdateDraft(draft.localDraftId, baseVersion, patch)
                                    },
                                    onDiscard: {
                                        onDiscardDraft(draft.localDraftId)
                                    }
                                )
                            }
                        }
                        ForEach(draftsWithoutMessage) { draft in
                            EmailThreadDraftCard(
                                draft: draft,
                                errorMessage: draftErrorMessages[draft.localDraftId],
                                onUpdateDraft: { baseVersion, patch in
                                    onUpdateDraft(draft.localDraftId, baseVersion, patch)
                                },
                                onDiscard: {
                                    onDiscardDraft(draft.localDraftId)
                                }
                            )
                        }
                    }
                    .padding(14)
                    .padding(.bottom, bottomContentInset)
                    .frame(minHeight: proxy.size.height, alignment: .top)
                }
            }
        } else {
            centeredState(
                systemName: "envelope",
                title: String(localized: "email.detail.placeholder", defaultValue: "Select an email"),
                message: nil
            )
        }
    }

    private func draftsForMessage(_ messageId: String) -> [EmailDraftSnapshot] {
        drafts.filter { $0.targetMessageId == messageId }
    }

    private var draftsWithoutMessage: [EmailDraftSnapshot] {
        drafts.filter { $0.targetMessageId == nil }
    }

    private func htmlBodyMinHeight(
        for message: EmailThreadMessage,
        in detail: EmailThreadDetail,
        viewportHeight: CGFloat
    ) -> CGFloat? {
        guard detail.messages.count == 1,
              expandedMessageIds.contains(message.id) else {
            return nil
        }
        return max(360, viewportHeight - 122)
    }

    private var displaySubject: String {
        let trimmed = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return detail?.messages.compactMap(\.subject).first(where: { !$0.isEmpty })
            ?? String(localized: "email.detail.noSubject", defaultValue: "(no subject)")
    }

    private var headerSubtitle: String {
        guard let detail else {
            return String(localized: "email.detail.thread", defaultValue: "Gmail thread")
        }
        return String.localizedStringWithFormat(
            String(localized: "email.detail.messageCount", defaultValue: "%lld messages"),
            detail.messages.count
        )
    }

    private func centeredState(systemName: String, title: String, message: String?) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemName)
                .font(.system(size: 24))
                .foregroundColor(BVColor.fgFaint)
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(BVColor.fgMute)
            if let message, !message.isEmpty {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundColor(BVColor.fgFaint)
                    .multilineTextAlignment(.center)
                    .lineLimit(5)
                    .padding(.horizontal, 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct EmailThreadCardContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(BVColor.bgInput)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(BVColor.border)
                )
        )
    }
}

private enum EmailToolbarActionMetrics {
    static let buttonWidth: CGFloat = 16
    static let buttonHeight: CGFloat = 22
    static let groupSpacing: CGFloat = 0
    static let iconSize: CGFloat = 12
    static let pairedButtonWidth: CGFloat = 18
    static let pairedSpacing: CGFloat = 1
}

private struct EmailHeaderIconButton: View {
    let systemName: String
    let label: String
    let iconSize: CGFloat
    let iconWeight: Font.Weight
    let boxWidth: CGFloat
    let boxHeight: CGFloat
    let isDisabled: Bool
    let isShowingProgress: Bool
    let foregroundColor: Color
    let action: () -> Void

    init(
        systemName: String,
        label: String,
        iconSize: CGFloat = EmailToolbarActionMetrics.iconSize,
        iconWeight: Font.Weight = .medium,
        boxWidth: CGFloat = EmailToolbarActionMetrics.buttonWidth,
        boxHeight: CGFloat = EmailToolbarActionMetrics.buttonHeight,
        isDisabled: Bool = false,
        isShowingProgress: Bool = false,
        foregroundColor: Color,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.label = label
        self.iconSize = iconSize
        self.iconWeight = iconWeight
        self.boxWidth = boxWidth
        self.boxHeight = boxHeight
        self.isDisabled = isDisabled
        self.isShowingProgress = isShowingProgress
        self.foregroundColor = foregroundColor
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Color.clear
                if isShowingProgress {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.72)
                } else {
                    Image(systemName: systemName)
                        .font(.system(size: iconSize, weight: iconWeight))
                        .foregroundColor(foregroundColor)
                }
            }
            .frame(width: boxWidth, height: boxHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: boxWidth, height: boxHeight, alignment: .center)
        .contentShape(Rectangle())
        .disabled(isDisabled)
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct EmailThreadMessageCard: View {
    let message: EmailThreadMessage
    let isExpanded: Bool
    let htmlBodyMinHeight: CGFloat?
    let onToggle: () -> Void
    let onCreateReply: () -> Void
    let onOpenURL: (URL) -> Void

    var body: some View {
        EmailThreadCardContainer {
            HStack(alignment: .top, spacing: 10) {
                EmailDetailAvatarDot(initial: senderInitial, color: BrainPersonColor.color(for: senderTitle))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onToggle)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .center, spacing: 6) {
                        HStack(spacing: 6) {
                            Text(senderTitle)
                                .font(.system(size: 12.5, weight: message.isUnread ? .semibold : .medium))
                                .foregroundColor(BVColor.fg)
                                .lineLimit(1)
                            if message.isUnread {
                                Circle()
                                    .fill(BVColor.accent)
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .frame(height: EmailToolbarActionMetrics.buttonHeight, alignment: .center)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onToggle)

                        Spacer(minLength: 4)
                        Text(timestampText)
                            .font(.system(size: 11))
                            .foregroundColor(BVColor.fgFaint)
                            .lineLimit(1)
                            .frame(height: EmailToolbarActionMetrics.buttonHeight, alignment: .center)
                            .fixedSize(horizontal: true, vertical: false)
                        HStack(alignment: .center, spacing: EmailToolbarActionMetrics.pairedSpacing) {
                            EmailHeaderIconButton(
                                systemName: "arrowshape.turn.up.left",
                                label: String(localized: "email.draft.reply", defaultValue: "Reply"),
                                boxWidth: EmailToolbarActionMetrics.pairedButtonWidth,
                                foregroundColor: BVColor.fgMute,
                                action: onCreateReply
                            )

                            EmailHeaderIconButton(
                                systemName: isExpanded ? "chevron.up" : "chevron.down",
                                label: isExpanded
                                    ? String(localized: "email.detail.collapseMessage", defaultValue: "Collapse message")
                                    : String(localized: "email.detail.expandMessage", defaultValue: "Expand message"),
                                iconWeight: .semibold,
                                boxWidth: EmailToolbarActionMetrics.pairedButtonWidth,
                                foregroundColor: BVColor.fgFaint,
                                action: onToggle
                            )
                        }
                        .frame(height: EmailToolbarActionMetrics.buttonHeight, alignment: .center)
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    .frame(height: EmailToolbarActionMetrics.buttonHeight, alignment: .center)
                    if !isExpanded {
                        Text(collapsedPreview)
                            .font(.system(size: 11.5))
                            .foregroundColor(BVColor.fgMute)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .contentShape(Rectangle())
                            .onTapGesture(perform: onToggle)
                    } else {
                        recipientLine
                            .contentShape(Rectangle())
                            .onTapGesture(perform: onToggle)
                    }
                }
            }
            .padding(12)

            if isExpanded {
                Divider()
                    .padding(.leading, 46)
                bodyContent
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
            }
        }
    }

    @ViewBuilder
    private var recipientLine: some View {
        let address = message.fromEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !address.isEmpty || message.to?.isEmpty == false {
            Text(addressLine(from: address))
                .font(.system(size: 11))
                .foregroundColor(BVColor.fgFaint)
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var bodyContent: some View {
        if let html = message.bodyHtml?.trimmingCharacters(in: .whitespacesAndNewlines), !html.isEmpty {
            EmailHTMLBodyView(html: html, onOpenURL: onOpenURL)
                .frame(maxWidth: .infinity, minHeight: htmlBodyMinHeight ?? 360)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(BVColor.border.opacity(0.6)))
        } else if let text = plainTextBody, !text.isEmpty {
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(BVColor.fg.opacity(0.82))
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        } else {
            Text(String(localized: "email.detail.emptyBody", defaultValue: "No body content"))
                .font(.system(size: 12))
                .foregroundColor(BVColor.fgFaint)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var senderTitle: String {
        if message.isSent {
            return String(localized: "email.detail.sender.me", defaultValue: "Me")
        }
        return message.fromName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? message.fromEmail?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? String(localized: "email.detail.sender.unknown", defaultValue: "Unknown sender")
    }

    private var senderInitial: String {
        senderTitle.first.map { String($0).uppercased() } ?? "?"
    }

    private var timestampText: String {
        guard let receivedAt = message.receivedAt else { return "" }
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        let calendar = Calendar.autoupdatingCurrent
        if calendar.isDateInToday(receivedAt) {
            formatter.setLocalizedDateFormatFromTemplate("jm")
        } else if calendar.component(.year, from: receivedAt) == calendar.component(.year, from: Date()) {
            formatter.setLocalizedDateFormatFromTemplate("MMMMdEEEjm")
        } else {
            formatter.setLocalizedDateFormatFromTemplate("yMMMMdEEEjm")
        }
        return formatter.string(from: receivedAt)
    }

    private var collapsedPreview: String {
        plainTextBody?.replacingOccurrences(of: "\n", with: " ").nilIfEmpty
            ?? message.snippet?.nilIfEmpty
            ?? String(localized: "email.detail.emptyBody", defaultValue: "No body content")
    }

    private var plainTextBody: String? {
        message.bodyText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private func addressLine(from address: String) -> String {
        let to = message.to?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        if let to {
            return String.localizedStringWithFormat(
                String(localized: "email.detail.addressLine", defaultValue: "%@ to %@"),
                address,
                to
            )
        }
        return address
    }
}

private enum EmailDraftHeaderField: Hashable {
    case to
    case cc
    case bcc
    case subject
}

private struct EmailDraftHeaderEditState: Equatable {
    var toText: String
    var ccText: String
    var bccText: String
    var subjectText: String

    init(toText: String, ccText: String, bccText: String, subjectText: String) {
        self.toText = toText
        self.ccText = ccText
        self.bccText = bccText
        self.subjectText = subjectText
    }

    init(draft: EmailDraftSnapshot) {
        toText = Self.formatRecipients(draft.toRecipients)
        ccText = Self.formatRecipients(draft.ccRecipients)
        bccText = Self.formatRecipients(draft.bccRecipients)
        subjectText = draft.subject
    }

    func patch() -> EmailDraftPatch {
        EmailDraftPatch(
            subject: subjectText.trimmingCharacters(in: .whitespacesAndNewlines),
            toRecipients: Self.parseRecipients(toText),
            ccRecipients: Self.parseRecipients(ccText),
            bccRecipients: Self.parseRecipients(bccText)
        )
    }

    static func formatRecipients(_ recipients: [String]) -> String {
        recipients.joined(separator: ", ")
    }

    static func parseRecipients(_ value: String) -> [String] {
        value
            .split { character in
                character == "," || character == ";" || character == "\n"
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private struct EmailThreadDraftCard: View {
    let draft: EmailDraftSnapshot
    let errorMessage: String?
    let onUpdateDraft: (Int, EmailDraftPatch) -> Void
    let onDiscard: () -> Void

    @State private var bodyText: String
    @State private var saveTask: Task<Void, Never>?
    @State private var isApplyingDraftBody = false
    @State private var lastSubmittedBodyText: String
    @State private var toText: String
    @State private var ccText: String
    @State private var bccText: String
    @State private var subjectText: String
    @State private var headerSaveTask: Task<Void, Never>?
    @State private var isApplyingHeaderFields = false
    @State private var lastSubmittedHeaderState: EmailDraftHeaderEditState
    @State private var isEditingHeaderFields = false
    @FocusState private var focusedHeaderField: EmailDraftHeaderField?

    init(
        draft: EmailDraftSnapshot,
        errorMessage: String?,
        onUpdateDraft: @escaping (Int, EmailDraftPatch) -> Void,
        onDiscard: @escaping () -> Void
    ) {
        self.draft = draft
        self.errorMessage = errorMessage
        self.onUpdateDraft = onUpdateDraft
        self.onDiscard = onDiscard
        _bodyText = State(initialValue: draft.bodyText)
        _lastSubmittedBodyText = State(initialValue: draft.bodyText)
        let headerState = EmailDraftHeaderEditState(draft: draft)
        _toText = State(initialValue: headerState.toText)
        _ccText = State(initialValue: headerState.ccText)
        _bccText = State(initialValue: headerState.bccText)
        _subjectText = State(initialValue: headerState.subjectText)
        _lastSubmittedHeaderState = State(initialValue: headerState)
    }

    var body: some View {
        EmailThreadCardContainer {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(12)
                Divider()
                    .padding(.leading, 46)
                editor
                    .padding(12)
            }
        }
        .onChange(of: bodyText) { _, newValue in
            guard !isApplyingDraftBody else {
                isApplyingDraftBody = false
                return
            }
            guard newValue != draft.bodyText else {
                saveTask?.cancel()
                return
            }
            scheduleSave(newValue, baseVersion: draft.version)
        }
        .onChange(of: draft.version) { _, _ in
            syncBodyAfterDraftChange()
            syncHeaderAfterDraftChange()
        }
        .onChange(of: toText) { _, _ in
            handleHeaderTextChange()
        }
        .onChange(of: ccText) { _, _ in
            handleHeaderTextChange()
        }
        .onChange(of: bccText) { _, _ in
            handleHeaderTextChange()
        }
        .onChange(of: subjectText) { _, _ in
            handleHeaderTextChange()
        }
        .onDisappear {
            saveTask?.cancel()
            headerSaveTask?.cancel()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            EmailDetailAvatarDot(
                initial: String(localized: "email.draft.initial", defaultValue: "D"),
                color: BVColor.accent
            )
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 6) {
                    Text(displayName)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(BVColor.fg)
                        .lineLimit(1)
                        .frame(height: EmailToolbarActionMetrics.buttonHeight, alignment: .center)
                    Spacer(minLength: 4)
                    Text(statusText)
                        .font(.system(size: 11))
                        .foregroundColor(errorMessage == nil ? BVColor.fgFaint : BVColor.fgMute)
                        .lineLimit(1)
                        .frame(height: EmailToolbarActionMetrics.buttonHeight, alignment: .center)
                        .fixedSize(horizontal: true, vertical: false)
                        .help(errorMessage ?? statusText)
                    HStack(alignment: .center, spacing: EmailToolbarActionMetrics.pairedSpacing) {
                        EmailHeaderIconButton(
                            systemName: isEditingHeaderFields ? "checkmark" : "square.and.pencil",
                            label: isEditingHeaderFields
                                ? String(localized: "email.draft.doneEditing", defaultValue: "Done editing")
                                : String(localized: "email.draft.editFields", defaultValue: "Edit draft fields"),
                            iconWeight: .semibold,
                            boxWidth: EmailToolbarActionMetrics.pairedButtonWidth,
                            foregroundColor: BVColor.fgMute,
                            action: toggleHeaderEditing
                        )
                        EmailHeaderIconButton(
                            systemName: "trash",
                            label: String(localized: "email.draft.discard", defaultValue: "Discard draft"),
                            boxWidth: EmailToolbarActionMetrics.pairedButtonWidth,
                            foregroundColor: BVColor.fgMute,
                            action: onDiscard
                        )
                    }
                    .frame(height: EmailToolbarActionMetrics.buttonHeight, alignment: .center)
                    .fixedSize(horizontal: true, vertical: false)
                }
                .frame(height: EmailToolbarActionMetrics.buttonHeight, alignment: .center)

                headerFields

                if let errorMessage, !errorMessage.isEmpty {
                    Text(String.localizedStringWithFormat(
                        String(localized: "email.draft.errorLine", defaultValue: "Draft error: %@"),
                        errorMessage
                    ))
                    .font(.system(size: 11))
                    .foregroundColor(BVColor.fgMute)
                    .lineLimit(2)
                }
            }
        }
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5)
                .fill(BVColor.bg)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(BVColor.border.opacity(0.7))
                )

            TextEditor(text: $bodyText)
                .font(.system(size: 12))
                .foregroundColor(BVColor.fg.opacity(0.86))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 150)

            if bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(String(localized: "email.draft.placeholder", defaultValue: "Write a reply..."))
                    .font(.system(size: 12))
                    .foregroundColor(BVColor.fgFaint)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 15)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: 150)
    }

    private var headerFields: some View {
        VStack(alignment: .leading, spacing: 3) {
            headerFieldRow(
                label: String(localized: "email.draft.field.to", defaultValue: "To"),
                field: .to,
                text: $toText,
                placeholder: String(localized: "email.draft.placeholder.recipients", defaultValue: "email@example.com"),
                displayValue: recipientsDisplay(toText)
            )

            if isEditingHeaderFields || !EmailDraftHeaderEditState.parseRecipients(ccText).isEmpty {
                headerFieldRow(
                    label: String(localized: "email.draft.field.cc", defaultValue: "Cc"),
                    field: .cc,
                    text: $ccText,
                    placeholder: String(localized: "email.draft.placeholder.recipients", defaultValue: "email@example.com"),
                    displayValue: recipientsDisplay(ccText)
                )
            }

            if isEditingHeaderFields || !EmailDraftHeaderEditState.parseRecipients(bccText).isEmpty {
                headerFieldRow(
                    label: String(localized: "email.draft.field.bcc", defaultValue: "Bcc"),
                    field: .bcc,
                    text: $bccText,
                    placeholder: String(localized: "email.draft.placeholder.recipients", defaultValue: "email@example.com"),
                    displayValue: recipientsDisplay(bccText)
                )
            }

            headerFieldRow(
                label: String(localized: "email.draft.field.subject", defaultValue: "Subject"),
                field: .subject,
                text: $subjectText,
                placeholder: String(localized: "email.draft.placeholder.subject", defaultValue: "Subject"),
                displayValue: subjectText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    ?? String(localized: "email.detail.noSubject", defaultValue: "(no subject)"),
                isSubject: true
            )
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !isEditingHeaderFields {
                beginEditingHeaderFields()
            }
        }
    }

    private func headerFieldRow(
        label: String,
        field: EmailDraftHeaderField,
        text: Binding<String>,
        placeholder: String,
        displayValue: String,
        isSubject: Bool = false
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(BVColor.fgFaint)
                .frame(width: 58, alignment: .leading)

            if isEditingHeaderFields {
                TextField(placeholder, text: text)
                    .textFieldStyle(.plain)
                    .font(.system(size: isSubject ? 11.5 : 11, weight: isSubject ? .medium : .regular))
                    .foregroundColor(isSubject ? BVColor.fgMute : BVColor.fgFaint)
                    .focused($focusedHeaderField, equals: field)
                    .onSubmit {
                        finishEditingHeaderFields()
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(BVColor.bg)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(BVColor.border.opacity(0.7))
                            )
                    )
            } else {
                Text(displayValue)
                    .font(.system(size: isSubject ? 11.5 : 11, weight: isSubject ? .medium : .regular))
                    .foregroundColor(isSubject ? BVColor.fgMute : BVColor.fgFaint)
                    .lineLimit(isSubject ? 1 : 2)
            }
        }
    }

    private var displayName: String {
        let digits = draft.displayName
            .split(separator: " ")
            .last
            .flatMap { Int($0) }
        if let digits {
            return String.localizedStringWithFormat(
                String(localized: "email.draft.displayName", defaultValue: "Draft %lld"),
                digits
            )
        }
        return draft.displayName
    }

    private func recipientsDisplay(_ value: String) -> String {
        let recipients = EmailDraftHeaderEditState.parseRecipients(value)
        guard !recipients.isEmpty else {
            return String(localized: "email.draft.noRecipients", defaultValue: "No recipients")
        }
        return EmailDraftHeaderEditState.formatRecipients(recipients)
    }

    private func toggleHeaderEditing() {
        if isEditingHeaderFields {
            finishEditingHeaderFields()
        } else {
            beginEditingHeaderFields()
        }
    }

    private func beginEditingHeaderFields() {
        isEditingHeaderFields = true
        focusedHeaderField = .to
        Task { @MainActor in
            focusedHeaderField = .to
        }
    }

    private func finishEditingHeaderFields() {
        isEditingHeaderFields = false
        focusedHeaderField = nil
        handleHeaderTextChange()
    }

    private var currentHeaderState: EmailDraftHeaderEditState {
        EmailDraftHeaderEditState(
            toText: toText,
            ccText: ccText,
            bccText: bccText,
            subjectText: subjectText
        )
    }

    private func applyHeaderState(_ state: EmailDraftHeaderEditState) {
        toText = state.toText
        ccText = state.ccText
        bccText = state.bccText
        subjectText = state.subjectText
    }

    private func handleHeaderTextChange() {
        guard !isApplyingHeaderFields else { return }
        let headerState = currentHeaderState
        guard headerState != EmailDraftHeaderEditState(draft: draft) else {
            headerSaveTask?.cancel()
            return
        }
        scheduleHeaderSave(headerState, baseVersion: draft.version)
    }

    private func syncBodyAfterDraftChange() {
        guard bodyText != draft.bodyText else {
            lastSubmittedBodyText = draft.bodyText
            return
        }
        guard draft.bodyText != lastSubmittedBodyText else {
            scheduleSave(bodyText, baseVersion: draft.version)
            return
        }
        saveTask?.cancel()
        isApplyingDraftBody = true
        bodyText = draft.bodyText
        lastSubmittedBodyText = draft.bodyText
    }

    private func syncHeaderAfterDraftChange() {
        let draftHeaderState = EmailDraftHeaderEditState(draft: draft)
        let headerState = currentHeaderState
        guard headerState != draftHeaderState else {
            lastSubmittedHeaderState = draftHeaderState
            return
        }
        guard draftHeaderState != lastSubmittedHeaderState else {
            scheduleHeaderSave(headerState, baseVersion: draft.version)
            return
        }
        headerSaveTask?.cancel()
        isApplyingHeaderFields = true
        applyHeaderState(draftHeaderState)
        lastSubmittedHeaderState = draftHeaderState
        Task { @MainActor in
            isApplyingHeaderFields = false
        }
    }

    private var statusText: String {
        errorMessage == nil ? syncStateText : String(localized: "email.draft.sync.failed", defaultValue: "Failed")
    }

    private var syncStateText: String {
        switch draft.syncState {
        case .localOnly:
            return String(localized: "email.draft.sync.localOnly", defaultValue: "Local")
        case .dirty:
            return String(localized: "email.draft.sync.dirty", defaultValue: "Unsynced")
        case .saving:
            return String(localized: "email.draft.sync.saving", defaultValue: "Saving")
        case .synced:
            return String(localized: "email.draft.sync.synced", defaultValue: "Synced")
        case .failed:
            return String(localized: "email.draft.sync.failed", defaultValue: "Failed")
        case .sent:
            return String(localized: "email.draft.sync.sent", defaultValue: "Sent")
        }
    }

    private func scheduleSave(_ value: String, baseVersion: Int) {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 450_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            lastSubmittedBodyText = value
            saveTask = nil
            onUpdateDraft(baseVersion, EmailDraftPatch(bodyText: value))
        }
    }

    private func scheduleHeaderSave(_ value: EmailDraftHeaderEditState, baseVersion: Int) {
        headerSaveTask?.cancel()
        headerSaveTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 450_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            lastSubmittedHeaderState = value
            headerSaveTask = nil
            onUpdateDraft(baseVersion, value.patch())
        }
    }
}

private struct EmailHTMLBodyView: NSViewRepresentable {
    let html: String
    let onOpenURL: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onOpenURL: onOpenURL)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsBackForwardNavigationGestures = false
        webView.loadHTMLString(htmlDocument(for: html), baseURL: nil)
        context.coordinator.loadedHTML = html
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onOpenURL = onOpenURL
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        webView.loadHTMLString(htmlDocument(for: html), baseURL: nil)
    }

    private func htmlDocument(for body: String) -> String {
        let sanitized = sanitizeHTML(body)
        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data: cid: blob:; style-src 'unsafe-inline'; font-src data:; base-uri 'none'; form-action 'none';">
          <style>
            * { box-sizing: border-box; }
            html, body { margin: 0; padding: 0; background: transparent; color: \(cssTextColor); font: -apple-system-body; overflow-wrap: anywhere; }
            body { padding: 12px; }
            img { max-width: 100% !important; height: auto !important; }
            table { max-width: 100% !important; border-collapse: collapse; }
            pre { white-space: pre-wrap; word-break: break-word; }
            a { color: \(cssAccentColor); }
          </style>
        </head>
        <body>\(sanitized)</body>
        </html>
        """
    }

    private var cssTextColor: String {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? "#E8E8E8" : "#222222"
    }

    private var cssAccentColor: String {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? "#7DB7FF" : "#0B63CE"
    }

    private func sanitizeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"<script\b[^>]*>[\s\S]*?</script>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"<iframe\b[^>]*>[\s\S]*?</iframe>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\son[a-zA-Z]+\s*=\s*"[^"]*""#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\son[a-zA-Z]+\s*=\s*'[^']*'"#, with: "", options: .regularExpression)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onOpenURL: (URL) -> Void
        var loadedHTML: String?

        init(onOpenURL: @escaping (URL) -> Void) {
            self.onOpenURL = onOpenURL
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            preferences: WKWebpagePreferences,
            decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
        ) {
            preferences.allowsContentJavaScript = false

            // Untrusted email HTML may not silently navigate the user out to
            // external apps via <meta refresh> / scripted navigation / form
            // submit. Only a real user click on a link is routed to
            // NSWorkspace.open; everything else with an external scheme is
            // dropped, while same-document / loadHTMLString navigations
            // (about:blank or no scheme) are allowed so the view actually
            // renders.
            let externalSchemes: Set<String> = ["http", "https", "mailto"]
            let scheme = navigationAction.request.url?.scheme?.lowercased() ?? ""

            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url,
               externalSchemes.contains(scheme) {
                onOpenURL(url)
                decisionHandler(.cancel, preferences)
                return
            }

            if externalSchemes.contains(scheme) {
                // Auto-navigation to an external scheme without a real user
                // click — drop.
                decisionHandler(.cancel, preferences)
                return
            }

            decisionHandler(.allow, preferences)
        }
    }
}

private struct EmailDetailAvatarDot: View {
    let initial: String
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .overlay(
                Text(initial)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
            )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
