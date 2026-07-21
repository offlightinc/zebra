import Foundation
import XCTest
@testable import ZebraVault

final class ZebraSourceOnboardingRuntimeInstallationTests: XCTestCase {
    func testInstalledCLIResolvesOnlyItsPrivateRuntimeFromUnrelatedWorkingDirectory() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let stateURL = root.appendingPathComponent("support/source-onboarding-state.json", isDirectory: false)
        let helper = ZebraSourceOnboardingHelper(stateURL: stateURL, homeDirectoryPath: root.path)
        let launch = try helper.prepareLaunchResult(selectedVaultPath: nil).get()

        let ambient = root.appendingPathComponent("ambient", isDirectory: true)
        let unrelated = root.appendingPathComponent("unrelated", isDirectory: true)
        try FileManager.default.createDirectory(at: ambient, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: true)
        try "raise RuntimeError('ambient common.py must not load')\n".write(
            to: ambient.appendingPathComponent("common.py", isDirectory: false),
            atomically: true,
            encoding: .utf8
        )

        let result = try run(
            executable: URL(fileURLWithPath: launch.helperPath),
            arguments: ["status", "--json"],
            currentDirectory: unrelated,
            environment: [
                "PYTHONPATH": ambient.path,
                "ZEBRA_SOURCE_ONBOARDING_STATE": stateURL.path,
                "ZEBRA_SOURCE_ONBOARDING_HOME": root.path,
            ]
        )
        XCTAssertEqual(result.status, 0, result.stderr)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(result.stdout.utf8)) as? [String: Any])
        XCTAssertEqual(payload["statePath"] as? String, stateURL.path)
    }

    func testMissingAndPartialRuntimeResourcesFailExplicitly() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let stateURL = root.appendingPathComponent("support/source-onboarding-state.json", isDirectory: false)

        let missing = ZebraSourceOnboardingHelper(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            runtimeResourceLocator: { nil }
        ).prepareLaunchResult(selectedVaultPath: nil)
        XCTAssertEqual(failure(of: missing), .runtimeResourceMissing)

        let partial = root.appendingPathComponent("partial-runtime", isDirectory: true)
        try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: true)
        let manifest: [String: Any] = [
            "schemaVersion": 1,
            "runtimeVersion": "partial",
            "requiredFiles": ["main.py", "missing.py"],
        ]
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
            .write(to: partial.appendingPathComponent("manifest.json"), options: .atomic)
        try "print('{}')\n".write(
            to: partial.appendingPathComponent("main.py"),
            atomically: true,
            encoding: .utf8
        )
        let incomplete = ZebraSourceOnboardingHelper(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            runtimeResourceLocator: { partial }
        ).prepareLaunchResult(selectedVaultPath: nil)
        XCTAssertEqual(failure(of: incomplete), .runtimeResourceIncomplete)
    }

    func testRuntimeVersionReplacementDoesNotMixInstalledTrees() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let stateURL = root.appendingPathComponent("support/source-onboarding-state.json", isDirectory: false)
        let first = ZebraSourceOnboardingHelper(stateURL: stateURL, homeDirectoryPath: root.path)
        _ = try first.prepareLaunchResult(selectedVaultPath: nil).get()

        let installed = stateURL.deletingLastPathComponent()
            .appendingPathComponent("source-onboarding-runtime", isDirectory: true)
        let staleOnly = installed.appendingPathComponent("stale-only.py", isDirectory: false)
        try "stale\n".write(to: staleOnly, atomically: true, encoding: .utf8)

        let replacement = root.appendingPathComponent("replacement-runtime", isDirectory: true)
        try FileManager.default.copyItem(at: installed, to: replacement)
        try FileManager.default.removeItem(at: replacement.appendingPathComponent("stale-only.py"))
        let manifestURL = replacement.appendingPathComponent("manifest.json", isDirectory: false)
        var manifest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        )
        manifest["runtimeVersion"] = "replacement-test"
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            .write(to: manifestURL, options: .atomic)

        let second = ZebraSourceOnboardingHelper(
            stateURL: stateURL,
            homeDirectoryPath: root.path,
            runtimeResourceLocator: { replacement }
        )
        _ = try second.prepareLaunchResult(selectedVaultPath: nil).get()

        XCTAssertFalse(FileManager.default.fileExists(atPath: staleOnly.path))
        let installedManifest = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: installed.appendingPathComponent("manifest.json"))
            ) as? [String: Any]
        )
        XCTAssertEqual(installedManifest["runtimeVersion"] as? String, "replacement-test")
        for path in try XCTUnwrap(installedManifest["requiredFiles"] as? [String]) {
            XCTAssertTrue(FileManager.default.fileExists(atPath: installed.appendingPathComponent(path).path), path)
        }
    }

    private func failure(
        of result: Result<ZebraSourceOnboardingHelper.LaunchContext, ZebraSourceOnboardingHelper.InstallationError>
    ) -> ZebraSourceOnboardingHelper.InstallationError? {
        if case let .failure(error) = result { return error }
        return nil
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ZebraSourceOnboardingRuntimeInstallationTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func run(
        executable: URL,
        arguments: [String],
        currentDirectory: URL,
        environment: [String: String]
    ) throws -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        return (
            process.terminationStatus,
            String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        )
    }
}
