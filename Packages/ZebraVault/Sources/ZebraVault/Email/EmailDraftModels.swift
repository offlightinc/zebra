import Foundation

public enum EmailDraftMode: String, Sendable {
    case reply
    case forward
    case compose
}

public enum EmailDraftOrigin: String, Sendable {
    case user
    case agent
    case gmail
}

public enum EmailDraftStatus: String, Sendable {
    case active
    case discarded
    case sent
}

public enum EmailDraftSyncState: String, Sendable {
    case localOnly
    case dirty
    case saving
    case synced
    case failed
    case sent
}

public struct EmailDraftSnapshot: Identifiable, Equatable, Sendable {
    public var id: String { localDraftId }

    public let localDraftId: String
    public let threadId: String
    public let providerThreadId: String?
    public let targetMessageId: String?
    public let providerDraftId: String?
    public let providerMessageId: String?
    public let accountEmail: String?
    public let mode: EmailDraftMode
    public let displayName: String
    public let origin: EmailDraftOrigin
    public let status: EmailDraftStatus
    public let syncState: EmailDraftSyncState
    public let version: Int
    public let toRecipients: [String]
    public let ccRecipients: [String]
    public let bccRecipients: [String]
    public let subject: String
    public let bodyHtml: String
    public let bodyText: String
    public let inReplyToHeader: String?
    public let referencesHeader: String?
    public let lastError: String?
    public let createdAt: Date
    public let updatedAt: Date
    public let syncedAt: Date?
    public let sentAt: Date?

    public init(
        localDraftId: String,
        threadId: String,
        providerThreadId: String?,
        targetMessageId: String?,
        providerDraftId: String?,
        providerMessageId: String?,
        accountEmail: String?,
        mode: EmailDraftMode,
        displayName: String,
        origin: EmailDraftOrigin,
        status: EmailDraftStatus,
        syncState: EmailDraftSyncState,
        version: Int,
        toRecipients: [String],
        ccRecipients: [String],
        bccRecipients: [String],
        subject: String,
        bodyHtml: String,
        bodyText: String,
        inReplyToHeader: String?,
        referencesHeader: String?,
        lastError: String?,
        createdAt: Date,
        updatedAt: Date,
        syncedAt: Date?,
        sentAt: Date?
    ) {
        self.localDraftId = localDraftId
        self.threadId = threadId
        self.providerThreadId = providerThreadId
        self.targetMessageId = targetMessageId
        self.providerDraftId = providerDraftId
        self.providerMessageId = providerMessageId
        self.accountEmail = accountEmail
        self.mode = mode
        self.displayName = displayName
        self.origin = origin
        self.status = status
        self.syncState = syncState
        self.version = version
        self.toRecipients = toRecipients
        self.ccRecipients = ccRecipients
        self.bccRecipients = bccRecipients
        self.subject = subject
        self.bodyHtml = bodyHtml
        self.bodyText = bodyText
        self.inReplyToHeader = inReplyToHeader
        self.referencesHeader = referencesHeader
        self.lastError = lastError
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncedAt = syncedAt
        self.sentAt = sentAt
    }
}

public struct EmailDraftCreateRequest: Sendable {
    public let threadId: String
    public let providerThreadId: String?
    public let targetMessageId: String?
    public let accountEmail: String?
    public let mode: EmailDraftMode
    public let origin: EmailDraftOrigin
    public let toRecipients: [String]
    public let ccRecipients: [String]
    public let bccRecipients: [String]
    public let subject: String
    public let bodyText: String
    public let inReplyToHeader: String?
    public let referencesHeader: String?

    public init(
        threadId: String,
        providerThreadId: String?,
        targetMessageId: String?,
        accountEmail: String?,
        mode: EmailDraftMode,
        origin: EmailDraftOrigin,
        toRecipients: [String],
        ccRecipients: [String] = [],
        bccRecipients: [String] = [],
        subject: String,
        bodyText: String,
        inReplyToHeader: String?,
        referencesHeader: String?
    ) {
        self.threadId = threadId
        self.providerThreadId = providerThreadId
        self.targetMessageId = targetMessageId
        self.accountEmail = accountEmail
        self.mode = mode
        self.origin = origin
        self.toRecipients = toRecipients
        self.ccRecipients = ccRecipients
        self.bccRecipients = bccRecipients
        self.subject = subject
        self.bodyText = bodyText
        self.inReplyToHeader = inReplyToHeader
        self.referencesHeader = referencesHeader
    }
}

public struct EmailDraftPatch: Sendable {
    public let bodyText: String?

    public init(bodyText: String? = nil) {
        self.bodyText = bodyText
    }
}
