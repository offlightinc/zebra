import Foundation

public struct ZebraAgentInstallCandidate: Identifiable, Equatable, Sendable {
    public let id: ZebraAgentKind
    public let displayName: String
    public let binaryName: String
    public let executablePath: String?
    public let appBundlePath: String?
    public let version: String?
    public let installState: ZebraAgentInstallState
    public let authState: ZebraAgentAuthState
    public let terminalLaunchable: Bool
    public let recommendedAction: ZebraAgentOnboardingAction

    public init(
        id: ZebraAgentKind,
        displayName: String,
        binaryName: String,
        executablePath: String?,
        appBundlePath: String?,
        version: String?,
        installState: ZebraAgentInstallState,
        authState: ZebraAgentAuthState,
        terminalLaunchable: Bool,
        recommendedAction: ZebraAgentOnboardingAction
    ) {
        self.id = id
        self.displayName = displayName
        self.binaryName = binaryName
        self.executablePath = executablePath
        self.appBundlePath = appBundlePath
        self.version = version
        self.installState = installState
        self.authState = authState
        self.terminalLaunchable = terminalLaunchable
        self.recommendedAction = recommendedAction
    }
}

public enum ZebraAgentInstallState: Equatable, Sendable {
    case installed
    case missing
    case broken(reason: String)
}

public enum ZebraAgentAuthState: String, Equatable, Sendable {
    case unknown
    case configPresent
    case probablySignedOut
}

public enum ZebraAgentOnboardingAction: String, Equatable, Sendable {
    case launch
    case install
    case repairInstall
}

public struct ZebraVersionCommandResult: Equatable, Sendable {
    public let exitCode: Int32?
    public let stdout: String
    public let stderr: String
    public let timedOut: Bool

    public init(exitCode: Int32?, stdout: String, stderr: String, timedOut: Bool = false) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
    }
}
