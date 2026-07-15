import XCTest
@testable import ZebraVault

final class ZebraAgentInstallScannerTests: XCTestCase {
    func testResolverJSONIsTheScannerSourceOfTruth() throws {
        let path = "/Users/test/custom tools/codex"
        let scanner = ZebraAgentInstallScanner(environment: makeEnvironment(json: responseJSON([
            candidate(.claude, state: "missing"),
            candidate(.codex, path: path, version: "codex 1.2.3", state: "installed", source: "loginShell"),
            candidate(.antigravity, state: "missing"),
        ])))

        let candidates = scanner.scan()
        let codex = try XCTUnwrap(candidates.first { $0.id == .codex })
        XCTAssertEqual(candidates.map(\.id), [.claude, .codex, .antigravity])
        XCTAssertEqual(codex.installState, .installed)
        XCTAssertEqual(codex.executablePath, path)
        XCTAssertEqual(codex.version, "codex 1.2.3")
        XCTAssertEqual(codex.discoverySource, .loginShell)
        XCTAssertTrue(codex.terminalLaunchable)
    }

    func testExecutableWhoseVersionCommandFailsIsNotInstalled() throws {
        let diagnostic = "/Users/test/.local/bin/codex --version failed"
        let scanner = ZebraAgentInstallScanner(environment: makeEnvironment(json: responseJSON([
            candidate(.claude, state: "missing"),
            candidate(.codex, state: "broken", diagnostic: diagnostic),
            candidate(.antigravity, state: "missing"),
        ])))

        let codex = try XCTUnwrap(scanner.scan().first { $0.id == .codex })
        guard case .broken(let reason) = codex.installState else {
            return XCTFail("Expected a CLI that cannot run to require repair")
        }
        XCTAssertEqual(reason, diagnostic)
        XCTAssertFalse(codex.terminalLaunchable)
        XCTAssertNil(codex.executablePath)
    }

    func testExecutableWhoseVersionCommandTimesOutIsNotInstalled() throws {
        let diagnostic = "/Users/test/.local/bin/claude --version timed out"
        let scanner = ZebraAgentInstallScanner(environment: makeEnvironment(json: responseJSON([
            candidate(.claude, state: "broken", diagnostic: diagnostic),
            candidate(.codex, state: "missing"),
            candidate(.antigravity, state: "missing"),
        ])))

        let claude = try XCTUnwrap(scanner.scan().first { $0.id == .claude })
        guard case .broken(let reason) = claude.installState else {
            return XCTFail("Expected a timed-out CLI to require repair")
        }
        XCTAssertEqual(reason, diagnostic)
        XCTAssertFalse(claude.terminalLaunchable)
        XCTAssertNil(claude.executablePath)
    }

    func testResolverFailureIsRecoverableBrokenStateNotMissing() {
        let environment = ZebraAgentScanEnvironment(
            resolverExecutablePath: "/tmp/zebra-agent-resolver",
            runResolver: { _, _ in
                ZebraVersionCommandResult(exitCode: 1, stdout: "", stderr: "resolver unavailable")
            }
        )

        let candidates = ZebraAgentInstallScanner(environment: environment).scan()

        XCTAssertTrue(candidates.allSatisfy { candidate in
            guard case .broken(let reason) = candidate.installState else { return false }
            return reason == "resolver unavailable" && !candidate.terminalLaunchable
        })
    }

    func testBundledResolverFindsCLIFromInteractiveLoginShellBeforeKnownPaths() throws {
        let fixture = try makeResolverFixture(binary: "codex", version: "codex fixture 9.9.9")
        let result = try runBundledResolver(home: fixture.home, timeout: 5)
        let scanner = ZebraAgentInstallScanner(environment: makeEnvironment(json: result))

        let codex = try XCTUnwrap(scanner.scan().first { $0.id == .codex })

        XCTAssertEqual(codex.installState, .installed)
        XCTAssertEqual(codex.executablePath, fixture.executable.path)
        XCTAssertEqual(codex.version, "codex fixture 9.9.9")
        XCTAssertEqual(codex.discoverySource, .loginShell)
    }

    func testBundledResolverRejectsAliasWithoutAbsoluteExecutablePath() throws {
        let home = try makeTemporaryDirectory()
        try "alias codex='printf codex-fixture'\n".write(
            to: home.appendingPathComponent(".zshrc"),
            atomically: true,
            encoding: .utf8
        )

        let result = try runBundledResolver(home: home, timeout: 2)
        let scanner = ZebraAgentInstallScanner(environment: makeEnvironment(json: result))
        let codex = try XCTUnwrap(scanner.scan().first { $0.id == .codex })

        XCTAssertEqual(codex.installState, .missing)
        XCTAssertFalse(codex.terminalLaunchable)
    }

    func testBundledResolverTimesOutShellStartupAndReturns() throws {
        let home = try makeTemporaryDirectory()
        try "sleep 10\n".write(
            to: home.appendingPathComponent(".zshrc"),
            atomically: true,
            encoding: .utf8
        )
        let started = Date()

        let result = try runBundledResolver(home: home, timeout: 1)

        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
        let scanner = ZebraAgentInstallScanner(environment: makeEnvironment(json: result))
        XCTAssertTrue(scanner.scan().allSatisfy { !$0.terminalLaunchable })
    }

    func testBundledResolverIgnoresPollutedShellOutput() throws {
        let fixture = try makeResolverFixture(binary: "codex", version: "codex fixture 1.0")
        let rc = fixture.home.appendingPathComponent(".zshrc")
        let existing = try String(contentsOf: rc)
        try ("printf 'shell-noise\\n'\n" + existing).write(to: rc, atomically: true, encoding: .utf8)

        let result = try runBundledResolver(home: fixture.home, timeout: 2)
        let codex = try XCTUnwrap(ZebraAgentInstallScanner(environment: makeEnvironment(json: result)).scan().first { $0.id == .codex })

        XCTAssertEqual(codex.installState, .installed)
        XCTAssertEqual(codex.executablePath, fixture.executable.path)
    }

    func testBundledResolverRejectsNonExecutableCandidate() throws {
        let home = try makeTemporaryDirectory()
        let bin = home.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let executable = bin.appendingPathComponent("codex")
        try "#!/bin/sh\nexit 0\n".write(to: executable, atomically: true, encoding: .utf8)

        let result = try runBundledResolver(home: home, timeout: 2, searchPath: bin.path, skipLoginShell: true)
        let codex = try XCTUnwrap(ZebraAgentInstallScanner(environment: makeEnvironment(json: result)).scan().first { $0.id == .codex })

        guard case .broken = codex.installState else { return XCTFail("Expected non-executable candidate to require repair") }
        XCTAssertFalse(codex.terminalLaunchable)
    }

    func testBundledResolverRejectsTransientPathAndCmuxClaudeWrapper() throws {
        let home = try makeTemporaryDirectory()
        let bin = home.appendingPathComponent("DerivedData/build/Products/Debug/Test.app/Contents/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let codex = bin.appendingPathComponent("codex")
        try "#!/bin/sh\nexit 0\n".write(to: codex, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: codex.path)
        let wrapperBin = home.appendingPathComponent("wrapper-bin", isDirectory: true)
        try FileManager.default.createDirectory(at: wrapperBin, withIntermediateDirectories: true)
        let claude = wrapperBin.appendingPathComponent("claude")
        try "#!/bin/sh\n# cmux claude wrapper - injects hooks and session tracking\nexit 0\n".write(to: claude, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: claude.path)

        let searchPath = [bin.path, wrapperBin.path].joined(separator: ":")
        let result = try runBundledResolver(home: home, timeout: 2, searchPath: searchPath, skipLoginShell: true)
        let candidates = ZebraAgentInstallScanner(environment: makeEnvironment(json: result)).scan()

        XCTAssertEqual(candidates.first { $0.id == .codex }?.installState, .missing)
        XCTAssertEqual(candidates.first { $0.id == .claude }?.installState, .missing)
    }

    private func makeEnvironment(json: String) -> ZebraAgentScanEnvironment {
        ZebraAgentScanEnvironment(
            resolverExecutablePath: "/tmp/zebra-agent-resolver",
            runResolver: { _, _ in ZebraVersionCommandResult(exitCode: 0, stdout: json, stderr: "") }
        )
    }

    private func responseJSON(_ candidates: [String]) -> String {
        "{\"schemaVersion\":1,\"candidates\":[\(candidates.joined(separator: ","))]}"
    }

    private func candidate(
        _ agent: ZebraAgentKind,
        path: String? = nil,
        version: String? = nil,
        state: String,
        source: String? = nil,
        diagnostic: String? = nil
    ) -> String {
        let launchable = state == "installed"
        let action = launchable ? "launch" : state == "missing" ? "install" : "repairInstall"
        return """
        {"id":\(json(agent.rawValue)),"displayName":\(json(agent.displayName)),"binaryName":\(json(agent.binaryName)),"executablePath":\(jsonNullable(path)),"version":\(jsonNullable(version)),"installState":\(json(state)),"authState":"unknown","terminalLaunchable":\(launchable),"recommendedAction":\(json(action)),"discoverySource":\(jsonNullable(source)),"diagnostic":\(jsonNullable(diagnostic))}
        """
    }

    private func json(_ value: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [value])
        let array = String(data: data, encoding: .utf8)!
        return String(array.dropFirst().dropLast())
    }

    private func jsonNullable(_ value: String?) -> String {
        value.map(json) ?? "null"
    }

    private func makeResolverFixture(binary: String, version: String) throws -> (home: URL, executable: URL) {
        let home = try makeTemporaryDirectory()
        let bin = home.appendingPathComponent("custom tools", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let executable = bin.appendingPathComponent(binary)
        try "#!/bin/sh\nprintf '%s\\n' \(shellQuote(version))\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let rc = "export PATH=\(shellQuote(bin.path)):\"$PATH\"\n"
        try rc.write(to: home.appendingPathComponent(".zshrc"), atomically: true, encoding: .utf8)
        return (home, executable)
    }

    private func runBundledResolver(
        home: URL,
        timeout: Int,
        searchPath: String = "/usr/bin:/bin",
        skipLoginShell: Bool = false
    ) throws -> String {
        let resolver = try XCTUnwrap(ZebraAgentScanEnvironment.live.resolverExecutablePath)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [resolver, "scan"]
        process.environment = [
            "HOME": home.path,
            "PATH": "/usr/bin:/bin",
            "ZEBRA_AGENT_RESOLVER_HOME": home.path,
            "ZEBRA_AGENT_RESOLVER_PATH": searchPath,
            "ZEBRA_AGENT_RESOLVER_LOGIN_SHELL": "/bin/zsh",
            "ZEBRA_AGENT_RESOLVER_TIMEOUT_SECONDS": String(timeout),
            "ZEBRA_AGENT_RESOLVER_CODEX_INSTALL_DIR": home.appendingPathComponent("none").path,
            "ZEBRA_AGENT_RESOLVER_SKIP_LOGIN_SHELL": skipLoginShell ? "1" : "0",
        ]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        let error = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, error)
        return String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
