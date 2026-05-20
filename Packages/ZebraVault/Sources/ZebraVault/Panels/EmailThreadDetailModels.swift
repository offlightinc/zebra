import Foundation

public struct EmailThreadDetail: Equatable {
    public let threadId: String
    public let providerThreadId: String?
    public let accountEmail: String?
    public let cached: Bool
    public let messages: [EmailThreadMessage]

    public init(
        threadId: String,
        providerThreadId: String? = nil,
        accountEmail: String? = nil,
        cached: Bool,
        messages: [EmailThreadMessage]
    ) {
        self.threadId = threadId
        self.providerThreadId = providerThreadId
        self.accountEmail = accountEmail
        self.cached = cached
        self.messages = messages
    }
}

public struct EmailThreadMessage: Identifiable, Equatable {
    public let id: String
    public let internetMessageId: String?
    public let subject: String?
    public let fromName: String?
    public let fromEmail: String?
    public let to: String?
    public let cc: String?
    public let receivedAt: Date?
    public let snippet: String?
    public let labelIds: [String]
    public let isUnread: Bool
    public let isSent: Bool
    public let hasAttachment: Bool
    public let bodyText: String?
    public let bodyHtml: String?

    public init(
        id: String,
        internetMessageId: String?,
        subject: String?,
        fromName: String?,
        fromEmail: String?,
        to: String?,
        cc: String?,
        receivedAt: Date?,
        snippet: String?,
        labelIds: [String],
        isUnread: Bool,
        isSent: Bool,
        hasAttachment: Bool,
        bodyText: String?,
        bodyHtml: String?
    ) {
        self.id = id
        self.internetMessageId = internetMessageId
        self.subject = subject
        self.fromName = fromName
        self.fromEmail = fromEmail
        self.to = to
        self.cc = cc
        self.receivedAt = receivedAt
        self.snippet = snippet
        self.labelIds = labelIds
        self.isUnread = isUnread
        self.isSent = isSent
        self.hasAttachment = hasAttachment
        self.bodyText = bodyText
        self.bodyHtml = bodyHtml
    }
}
