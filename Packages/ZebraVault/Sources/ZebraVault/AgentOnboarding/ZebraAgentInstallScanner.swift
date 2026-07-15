import Foundation

public struct ZebraAgentScanEnvironment: Sendable {
    public let resolverExecutablePath: String?
    public let runResolver: @Sendable (String, TimeInterval) -> ZebraVersionCommandResult

    public init(
        resolverExecutablePath: String?,
        runResolver: @escaping @Sendable (String, TimeInterval) -> ZebraVersionCommandResult
    ) {
        self.resolverExecutablePath = resolverExecutablePath
        self.runResolver = runResolver
    }

    public static let live = ZebraAgentScanEnvironment(
        resolverExecutablePath: Bundle.module.url(
            forResource: "zebra-agent-resolver",
            withExtension: nil
        )?.path,
        runResolver: { executablePath, timeout in
            ZebraAgentInstallScanner.runCommand(
                executablePath: executablePath,
                arguments: ["scan"],
                timeout: timeout
            )
        }
    )
}

public struct ZebraAgentInstallScanner {
    private let environment: ZebraAgentScanEnvironment
    private let resolverTimeout: TimeInterval

    public init(environment: ZebraAgentScanEnvironment = .live, resolverTimeout: TimeInterval = 20) {
        self.environment = environment
        self.resolverTimeout = resolverTimeout
    }

    public func scan() -> [ZebraAgentInstallCandidate] {
        guard let resolverPath = environment.resolverExecutablePath else {
            return failedCandidates(reason: "agent resolver helper is missing")
        }
        let result = environment.runResolver(resolverPath, resolverTimeout)
        guard !result.timedOut else {
            return failedCandidates(reason: "agent resolver helper timed out")
        }
        guard result.exitCode == 0 else {
            let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return failedCandidates(reason: detail.isEmpty ? "agent resolver helper failed" : detail)
        }
        guard let data = result.stdout.data(using: .utf8),
              let response = try? JSONDecoder().decode(ResolverResponse.self, from: data),
              response.schemaVersion == 1 else {
            return failedCandidates(reason: "agent resolver helper returned invalid JSON")
        }

        let byID = Dictionary(uniqueKeysWithValues: response.candidates.map { ($0.id, $0) })
        return ZebraAgentKind.allCases.map { kind in
            guard let resolved = byID[kind] else {
                return failedCandidate(kind: kind, reason: "agent resolver omitted \(kind.rawValue)")
            }
            return resolved.candidate
        }
    }

    private func failedCandidates(reason: String) -> [ZebraAgentInstallCandidate] {
        ZebraAgentKind.allCases.map { failedCandidate(kind: $0, reason: reason) }
    }

    private func failedCandidate(kind: ZebraAgentKind, reason: String) -> ZebraAgentInstallCandidate {
        ZebraAgentInstallCandidate(
            id: kind,
            displayName: kind.displayName,
            binaryName: kind.binaryName,
            executablePath: nil,
            appBundlePath: nil,
            version: nil,
            installState: .broken(reason: reason),
            authState: .unknown,
            terminalLaunchable: false,
            recommendedAction: .repairInstall,
            discoverySource: nil,
            diagnostic: reason
        )
    }

    static func runCommand(
        executablePath: String,
        arguments: [String],
        timeout: TimeInterval
    ) -> ZebraVersionCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let group = DispatchGroup()
        group.enter()
        process.terminationHandler = { _ in group.leave() }
        do {
            try process.run()
        } catch {
            return ZebraVersionCommandResult(exitCode: nil, stdout: "", stderr: error.localizedDescription)
        }

        if group.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if group.wait(timeout: .now() + 0.25) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = group.wait(timeout: .now() + 0.25)
            }
            return ZebraVersionCommandResult(
                exitCode: process.isRunning ? nil : process.terminationStatus,
                stdout: String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
                stderr: String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
                timedOut: true
            )
        }

        return ZebraVersionCommandResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            stderr: String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }
}

private struct ResolverResponse: Decodable {
    let schemaVersion: Int
    let candidates: [ResolverCandidate]
}

private struct ResolverCandidate: Decodable {
    let id: ZebraAgentKind
    let displayName: String
    let binaryName: String
    let executablePath: String?
    let version: String?
    let installState: String
    let authState: ZebraAgentAuthState
    let terminalLaunchable: Bool
    let recommendedAction: ZebraAgentOnboardingAction
    let discoverySource: ZebraAgentDiscoverySource?
    let diagnostic: String?

    var candidate: ZebraAgentInstallCandidate {
        let state: ZebraAgentInstallState
        switch installState {
        case "installed": state = .installed
        case "missing": state = .missing
        default: state = .broken(reason: diagnostic ?? "agent resolver reported a broken install")
        }
        return ZebraAgentInstallCandidate(
            id: id,
            displayName: displayName,
            binaryName: binaryName,
            executablePath: executablePath,
            appBundlePath: nil,
            version: version,
            installState: state,
            authState: authState,
            terminalLaunchable: terminalLaunchable,
            recommendedAction: recommendedAction,
            discoverySource: discoverySource,
            diagnostic: diagnostic
        )
    }
}
