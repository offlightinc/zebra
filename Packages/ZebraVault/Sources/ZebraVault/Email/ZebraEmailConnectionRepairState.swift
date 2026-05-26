import Foundation

public struct ZebraEmailConnectionRepairState: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case configurationMissing
        case taskExpired
        case taskPendingApproval
        case authorizationFailed
        case taskUnavailable
        case provisioning
        case provisioningFailed
    }

    public let kind: Kind
    public let detail: String?
    public let taskId: String?

    public init(kind: Kind, detail: String? = nil, taskId: String? = nil) {
        self.kind = kind
        self.detail = detail
        self.taskId = taskId
    }
}
