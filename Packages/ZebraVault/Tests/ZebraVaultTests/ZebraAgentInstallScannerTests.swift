import XCTest
@testable import ZebraVault

final class ZebraAgentInstallScannerTests: XCTestCase {
    func testNoBinariesFoundReturnsMissingCandidates() {
        let scanner = ZebraAgentInstallScanner(environment: makeEnvironment())

        let candidates = scanner.scan()

        XCTAssertEqual(candidates.map(\.id), [.claude, .codex, .antigravity])
        XCTAssertTrue(candidates.allSatisfy { $0.installState == .missing })
        XCTAssertTrue(candidates.allSatisfy { !$0.terminalLaunchable })
    }

    func testOnlyCodexFoundReturnsInstalledCodex() throws {
        let codexPath = "/opt/homebrew/bin/codex"
        let scanner = ZebraAgentInstallScanner(
            environment: makeEnvironment(
                executablePaths: [codexPath],
                versions: [
                    codexPath: ZebraVersionCommandResult(
                        exitCode: 0,
                        stdout: "codex 0.42.0\n",
                        stderr: ""
                    ),
                ]
            )
        )

        let codex = try XCTUnwrap(scanner.scan().first { $0.id == .codex })

        XCTAssertEqual(codex.installState, .installed)
        XCTAssertEqual(codex.executablePath, codexPath)
        XCTAssertEqual(codex.version, "codex 0.42.0")
        XCTAssertEqual(codex.recommendedAction, .launch)
        XCTAssertTrue(codex.terminalLaunchable)
    }

    func testCodexStandalonePathIsPreferredOverHomebrewCandidate() throws {
        let standalonePath = "/Users/test/.local/bin/codex"
        let homebrewPath = "/opt/homebrew/bin/codex"
        let scanner = ZebraAgentInstallScanner(
            environment: makeEnvironment(
                executablePaths: [standalonePath, homebrewPath]
            )
        )

        let codex = try XCTUnwrap(scanner.scan().first { $0.id == .codex })

        XCTAssertEqual(codex.installState, .installed)
        XCTAssertEqual(codex.executablePath, standalonePath)
    }

    func testCodexInstallDirectoryIsPreferredOverKnownCandidates() throws {
        let customPath = "/Users/test/tools/bin/codex"
        let standalonePath = "/Users/test/.local/bin/codex"
        let scanner = ZebraAgentInstallScanner(
            environment: makeEnvironment(
                codexInstallDirectoryPath: "/Users/test/tools/bin",
                executablePaths: [customPath, standalonePath]
            )
        )

        let codex = try XCTUnwrap(scanner.scan().first { $0.id == .codex })

        XCTAssertEqual(codex.installState, .installed)
        XCTAssertEqual(codex.executablePath, customPath)
    }

    func testGeminiBinaryIsIgnoredForOnboardingCandidates() {
        let scanner = ZebraAgentInstallScanner(
            environment: makeEnvironment(
                searchPath: "/opt/homebrew/bin",
                executablePaths: ["/opt/homebrew/bin/gemini"]
            )
        )

        let candidates = scanner.scan()

        XCTAssertFalse(candidates.map { $0.binaryName }.contains("gemini"))
        XCTAssertTrue(candidates.allSatisfy { $0.installState == ZebraAgentInstallState.missing })
    }

    func testClaudeWrapperPathIsSkippedInFavorOfUserBinary() throws {
        let wrapperPath = "/opt/homebrew/bin/claude"
        let userPath = "/usr/local/bin/claude"
        let scanner = ZebraAgentInstallScanner(
            environment: makeEnvironment(
                executablePaths: [wrapperPath, userPath],
                filePrefixes: [
                    wrapperPath: "cmux claude wrapper - injects hooks and session tracking",
                    userPath: "#!/bin/sh\n",
                ]
            )
        )

        let claude = try XCTUnwrap(scanner.scan().first { $0.id == .claude })

        XCTAssertEqual(claude.installState, .installed)
        XCTAssertEqual(claude.executablePath, userPath)
    }

    func testNonExecutableKnownPathReturnsBrokenCandidate() throws {
        let scanner = ZebraAgentInstallScanner(
            environment: makeEnvironment(
                filePaths: ["/Users/test/.local/bin/agy"]
            )
        )

        let antigravity = try XCTUnwrap(scanner.scan().first { $0.id == .antigravity })

        guard case .broken(let reason) = antigravity.installState else {
            return XCTFail("Expected broken candidate")
        }
        XCTAssertTrue(reason.contains("is not executable"))
        XCTAssertEqual(antigravity.recommendedAction, .repairInstall)
    }

    func testExecutableWhoseVersionCommandFailsIsNotInstalled() throws {
        let codexPath = "/Users/test/.local/bin/codex"
        let scanner = ZebraAgentInstallScanner(
            environment: makeEnvironment(
                executablePaths: [codexPath],
                versions: [
                    codexPath: ZebraVersionCommandResult(
                        exitCode: 1,
                        stdout: "",
                        stderr: "runtime dependency missing"
                    ),
                ]
            )
        )

        let codex = try XCTUnwrap(scanner.scan().first { $0.id == .codex })

        guard case .broken(let reason) = codex.installState else {
            return XCTFail("Expected a CLI that cannot run to require repair")
        }
        XCTAssertTrue(reason.contains("--version"), reason)
        XCTAssertFalse(codex.terminalLaunchable)
        XCTAssertNil(codex.executablePath)
    }

    func testExecutableWhoseVersionCommandTimesOutIsNotInstalled() throws {
        let claudePath = "/Users/test/.local/bin/claude"
        let scanner = ZebraAgentInstallScanner(
            environment: makeEnvironment(
                executablePaths: [claudePath],
                versions: [
                    claudePath: ZebraVersionCommandResult(
                        exitCode: nil,
                        stdout: "",
                        stderr: "",
                        timedOut: true
                    ),
                ]
            )
        )

        let claude = try XCTUnwrap(scanner.scan().first { $0.id == .claude })

        guard case .broken(let reason) = claude.installState else {
            return XCTFail("Expected a timed-out CLI to require repair")
        }
        XCTAssertTrue(reason.contains("timed out"), reason)
        XCTAssertFalse(claude.terminalLaunchable)
        XCTAssertNil(claude.executablePath)
    }

    private func makeEnvironment(
        homeDirectoryPath: String = "/Users/test",
        searchPath: String = "/opt/homebrew/bin:/usr/local/bin:/Users/test/.local/bin",
        codexInstallDirectoryPath: String? = nil,
        filePaths: Set<String> = [],
        executablePaths: Set<String> = [],
        filePrefixes: [String: String] = [:],
        versions: [String: ZebraVersionCommandResult] = [:]
    ) -> ZebraAgentScanEnvironment {
        ZebraAgentScanEnvironment(
            homeDirectoryPath: homeDirectoryPath,
            searchPath: searchPath,
            codexInstallDirectoryPath: codexInstallDirectoryPath,
            fileExistsAtPath: { filePaths.contains($0) || executablePaths.contains($0) },
            isExecutableFileAtPath: { executablePaths.contains($0) },
            applicationPathForName: { _ in nil },
            filePrefixAtPath: { path, _ in filePrefixes[path] },
            runVersionCommand: { path, _, _ in
                versions[path] ?? ZebraVersionCommandResult(exitCode: 0, stdout: "", stderr: "")
            }
        )
    }
}
