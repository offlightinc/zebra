import AppKit
import SwiftUI
import WebKit

public struct ZebraEmailThreadDetailView: View {
    private let subject: String
    private let detail: EmailThreadDetail?
    private let isLoading: Bool
    private let errorMessage: String?
    private let expandedMessageIds: Set<String>
    /// Extra bottom padding on the scrollable thread body so a host-overlaid
    /// floating chat pill does not obscure the last message. Mirrors the
    /// pattern `ZebraMarkdownPanelView` uses (`.padding(.bottom, 160)` on the
    /// scrolled content). Defaults to 0 so non-host callers (previews, tests)
    /// render flush.
    private let bottomContentInset: CGFloat
    private let onRefresh: () -> Void
    private let onToggleMessage: (String) -> Void
    private let onOpenURL: (URL) -> Void

    public init(
        subject: String,
        detail: EmailThreadDetail?,
        isLoading: Bool,
        errorMessage: String?,
        expandedMessageIds: Set<String>,
        bottomContentInset: CGFloat = 0,
        onRefresh: @escaping () -> Void,
        onToggleMessage: @escaping (String) -> Void,
        onOpenURL: @escaping (URL) -> Void
    ) {
        self.subject = subject
        self.detail = detail
        self.isLoading = isLoading
        self.errorMessage = errorMessage
        self.expandedMessageIds = expandedMessageIds
        self.bottomContentInset = bottomContentInset
        self.onRefresh = onRefresh
        self.onToggleMessage = onToggleMessage
        self.onOpenURL = onOpenURL
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
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

            if let gmailURL = EmailThreadGmailURL.build(
                accountEmail: detail?.accountEmail,
                providerThreadId: detail?.providerThreadId
            ) {
                Button(action: { onOpenURL(gmailURL) }) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundColor(BVColor.fgMute)
                .help(String(localized: "email.detail.openInGmail", defaultValue: "Open in Gmail"))
                .accessibilityLabel(String(localized: "email.detail.openInGmail", defaultValue: "Open in Gmail"))
            }

            Button(action: onRefresh) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.72)
                        .frame(width: 22, height: 22)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 22, height: 22)
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(BVColor.fgMute)
            .disabled(isLoading)
            .help(String(localized: "email.detail.refresh", defaultValue: "Refresh"))
            .accessibilityLabel(String(localized: "email.detail.refresh", defaultValue: "Refresh"))
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(BVColor.bg)
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
                                onOpenURL: onOpenURL
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

private struct EmailThreadMessageCard: View {
    let message: EmailThreadMessage
    let isExpanded: Bool
    let htmlBodyMinHeight: CGFloat?
    let onToggle: () -> Void
    let onOpenURL: (URL) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onToggle) {
                HStack(alignment: .top, spacing: 10) {
                    EmailDetailAvatarDot(initial: senderInitial, color: BrainPersonColor.color(for: senderTitle))
                        .frame(width: 24, height: 24)

                    VStack(alignment: .leading, spacing: 3) {
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
                            Spacer(minLength: 4)
                            Text(timestampText)
                                .font(.system(size: 11))
                                .foregroundColor(BVColor.fgFaint)
                                .lineLimit(1)
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(BVColor.fgFaint)
                                .frame(width: 12, height: 12)
                        }
                        if !isExpanded {
                            Text(collapsedPreview)
                                .font(.system(size: 11.5))
                                .foregroundColor(BVColor.fgMute)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        } else {
                            recipientLine
                        }
                    }
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .padding(.leading, 46)
                bodyContent
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
            }
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
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
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
