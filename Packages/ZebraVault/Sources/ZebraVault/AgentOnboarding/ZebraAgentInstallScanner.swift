import Foundation

public struct ZebraAgentScanEnvironment: Sendable {
    public let homeDirectoryPath: String
    public let searchPath: String?
    public let codexInstallDirectoryPath: String?
    public let fileExistsAtPath: @Sendable (String) -> Bool
    public let isExecutableFileAtPath: @Sendable (String) -> Bool
    public let applicationPathForName: @Sendable (String) -> String?
    public let filePrefixAtPath: @Sendable (String, Int) -> String?
    public let runVersionCommand: @Sendable (String, [String], TimeInterval) -> ZebraVersionCommandResult

    public init(
        homeDirectoryPath: String,
        searchPath: String?,
        codexInstallDirectoryPath: String? = nil,
        fileExistsAtPath: @escaping @Sendable (String) -> Bool,
        isExecutableFileAtPath: @escaping @Sendable (String) -> Bool,
        applicationPathForName: @escaping @Sendable (String) -> String?,
        filePrefixAtPath: @escaping @Sendable (String, Int) -> String?,
        runVersionCommand: @escaping @Sendable (String, [String], TimeInterval) -> ZebraVersionCommandResult
    ) {
        self.homeDirectoryPath = homeDirectoryPath
        self.searchPath = searchPath
        self.codexInstallDirectoryPath = codexInstallDirectoryPath
        self.fileExistsAtPath = fileExistsAtPath
        self.isExecutableFileAtPath = isExecutableFileAtPath
        self.applicationPathForName = applicationPathForName
        self.filePrefixAtPath = filePrefixAtPath
        self.runVersionCommand = runVersionCommand
    }

    public static let live = ZebraAgentScanEnvironment(
        homeDirectoryPath: FileManager.default.homeDirectoryForCurrentUser.path,
        searchPath: ProcessInfo.processInfo.environment["PATH"],
        codexInstallDirectoryPath: ProcessInfo.processInfo.environment["CODEX_INSTALL_DIR"],
        fileExistsAtPath: { FileManager.default.fileExists(atPath: $0) },
        isExecutableFileAtPath: { FileManager.default.isExecutableFile(atPath: $0) },
        applicationPathForName: { _ in nil },
        filePrefixAtPath: { path, byteLimit in
            guard let data = FileManager.default.contents(atPath: path) else { return nil }
            return String(data: data.prefix(byteLimit), encoding: .utf8)
        },
        runVersionCommand: { executablePath, arguments, timeout in
            ZebraAgentInstallScanner.runVersionCommand(
                executablePath: executablePath,
                arguments: arguments,
                timeout: timeout
            )
        }
    )
}

public struct ZebraAgentInstallScanner {
    private let environment: ZebraAgentScanEnvironment
    private let versionTimeout: TimeInterval

    public init(environment: ZebraAgentScanEnvironment = .live, versionTimeout: TimeInterval = 2) {
        self.environment = environment
        self.versionTimeout = versionTimeout
    }

    public func scan() -> [ZebraAgentInstallCandidate] {
        ZebraAgentKind.allCases.map(candidate(for:))
    }

    private func candidate(for kind: ZebraAgentKind) -> ZebraAgentInstallCandidate {
        let resolution = resolveExecutable(for: kind)
        let appBundlePath = kind.applicationSearchNames.lazy.compactMap(environment.applicationPathForName).first
        let authState = authState(for: kind)

        switch resolution {
        case .installed(let executablePath):
            return ZebraAgentInstallCandidate(
                id: kind,
                displayName: kind.displayName,
                binaryName: kind.binaryName,
                executablePath: executablePath,
                appBundlePath: appBundlePath,
                version: versionString(for: kind, executablePath: executablePath),
                installState: .installed,
                authState: authState,
                terminalLaunchable: true,
                recommendedAction: .launch
            )
        case .missing:
            return ZebraAgentInstallCandidate(
                id: kind,
                displayName: kind.displayName,
                binaryName: kind.binaryName,
                executablePath: nil,
                appBundlePath: appBundlePath,
                version: nil,
                installState: .missing,
                authState: authState,
                terminalLaunchable: false,
                recommendedAction: .install
            )
        case .broken(let reason):
            return ZebraAgentInstallCandidate(
                id: kind,
                displayName: kind.displayName,
                binaryName: kind.binaryName,
                executablePath: nil,
                appBundlePath: appBundlePath,
                version: nil,
                installState: .broken(reason: reason),
                authState: authState,
                terminalLaunchable: false,
                recommendedAction: .repairInstall
            )
        }
    }

    private func resolveExecutable(for kind: ZebraAgentKind) -> ExecutableResolution {
        var firstBrokenReason: String?

        for path in executableCandidates(for: kind) {
            if environment.isExecutableFileAtPath(path) {
                guard !shouldSkipExecutable(path, kind: kind) else { continue }
                return .installed(path)
            }
            if environment.fileExistsAtPath(path), firstBrokenReason == nil {
                firstBrokenReason = "\(path) is not executable"
            }
        }

        if let firstBrokenReason {
            return .broken(reason: firstBrokenReason)
        }
        return .missing
    }

    private func executableCandidates(for kind: ZebraAgentKind) -> [String] {
        var candidates = kind.executablePathCandidates(homeDirectoryPath: environment.homeDirectoryPath)
        if kind == .codex,
           let codexInstallDirectoryPath = nonEmpty(environment.codexInstallDirectoryPath) {
            candidates.insert(
                URL(fileURLWithPath: codexInstallDirectoryPath, isDirectory: true)
                    .appendingPathComponent(kind.binaryName)
                    .path,
                at: 0
            )
        }

        let pathEntries = environment.searchPath?
            .split(separator: ":")
            .map(String.init) ?? []
        for entry in pathEntries where !entry.isEmpty {
            candidates.append(URL(fileURLWithPath: entry, isDirectory: true).appendingPathComponent(kind.binaryName).path)
        }

        return orderedUnique(candidates.map(standardizedPath))
    }

    private func shouldSkipExecutable(_ path: String, kind: ZebraAgentKind) -> Bool {
        guard !isTransientBuildPath(path) else { return true }
        guard kind == .claude else { return false }
        return isCmuxClaudeWrapper(at: path)
    }

    private func isTransientBuildPath(_ path: String) -> Bool {
        let lowercased = path.lowercased()
        return lowercased.contains("/deriveddata/")
            || lowercased.contains("/build/products/")
            || lowercased.contains(".app/contents/")
    }

    private func isCmuxClaudeWrapper(at path: String) -> Bool {
        environment.filePrefixAtPath(path, 512)?
            .contains("cmux claude wrapper - injects hooks and session tracking") == true
    }

    private func authState(for kind: ZebraAgentKind) -> ZebraAgentAuthState {
        kind.configHintPaths(homeDirectoryPath: environment.homeDirectoryPath).contains(where: environment.fileExistsAtPath)
            ? .configPresent
            : .unknown
    }

    private func versionString(for kind: ZebraAgentKind, executablePath: String) -> String? {
        let result = environment.runVersionCommand(executablePath, kind.versionArguments, versionTimeout)
        guard result.exitCode == 0, !result.timedOut else { return nil }
        let output = result.stdout.isEmpty ? result.stderr : result.stdout
        return output
            .split(whereSeparator: \.isNewline)
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    private func orderedUnique(_ paths: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for path in paths where seen.insert(path).inserted {
            result.append(path)
        }
        return result
    }

    private func standardizedPath(_ path: String) -> String {
        (path as NSString).standardizingPath
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    public static func runVersionCommand(
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
            return ZebraVersionCommandResult(
                exitCode: nil,
                stdout: "",
                stderr: error.localizedDescription
            )
        }

        let deadline = DispatchTime.now() + .milliseconds(Int(timeout * 1000))
        if group.wait(timeout: deadline) == .timedOut {
            process.terminate()
            _ = group.wait(timeout: .now() + .milliseconds(200))
            let isStillRunning = process.isRunning
            return ZebraVersionCommandResult(
                exitCode: isStillRunning ? nil : process.terminationStatus,
                stdout: isStillRunning ? "" : String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
                stderr: isStillRunning ? "" : String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
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

private enum ExecutableResolution: Equatable {
    case installed(String)
    case missing
    case broken(reason: String)
}
