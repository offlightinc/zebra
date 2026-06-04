import XCTest
@testable import ZebraVault

final class ZebraOnboardingChecklistStoreTests: XCTestCase {
    @MainActor
    func testCompletedGBrainReceiptDoesNotRunLiveProbeFromChecklist() async throws {
        let root = try makeTemporaryDirectory()
        let vault = root.appendingPathComponent("brain", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let log = root.appendingPathComponent("gbrain-probe.log", isDirectory: false)
        let executable = try installFakeGBrain(root: root, sourcePath: vault.path, log: log)
        let stateURL = root
            .appendingPathComponent("onboarding", isDirectory: true)
            .appendingPathComponent("gbrain-setup-state.json", isDirectory: false)
        try writeCompletedGBrainState(stateURL: stateURL, vaultPath: vault.path, executablePath: executable.path)

        let store = ZebraOnboardingChecklistStore(
            homeDirectoryPath: root.path,
            gbrainOnboardingStateURL: stateURL
        )
        store.syncExternalState(selectedVaultPath: vault.path, emailConnected: false)

        try? await Task.sleep(nanoseconds: 300_000_000)

        XCTAssertTrue(store.completedStepIDs.contains(.gbrain))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: log.path),
            "Completed receipts should be trusted by the checklist without running gbrain doctor/current/list."
        )
    }

    private func writeCompletedGBrainState(
        stateURL: URL,
        vaultPath: String,
        executablePath: String
    ) throws {
        let targetKey = "vault:\(vaultPath)"
        let timestamp = "2026-06-04T00:00:00Z"
        let target: [String: Any] = [
            "vaultPath": vaultPath,
            "sourceId": "brain",
            "gbrainExecutablePath": executablePath,
            "doctorStatus": ["ok": true, "status": "ok"],
            "sourcesCurrentResult": [
                "ok": true,
                "sourceId": "brain",
                "localPath": vaultPath,
            ],
            "searchProbeResult": ["ok": true, "status": "not_run"],
            "verifiedAt": timestamp,
            "complete": true,
            "targetResolution": [
                "method": "user_created_repo",
                "confirmedAt": timestamp,
            ],
            "reasons": [],
        ]
        let state: [String: Any] = [
            "schemaVersion": 1,
            "progress": [
                "resolvedTargetKey": targetKey,
                "targetResolution": [
                    "status": "verified",
                    "method": "user_created_repo",
                    "confirmedAt": timestamp,
                ],
            ],
            "receipt": [
                "globalReadiness": [
                    "complete": true,
                    "gbrainExecutablePath": executablePath,
                    "doctorOk": true,
                    "verifiedAt": timestamp,
                ],
                "primaryTargetKey": targetKey,
                "targets": [
                    targetKey: target,
                ],
            ],
        ]
        try FileManager.default.createDirectory(
            at: stateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: stateURL, options: .atomic)
    }

    private func installFakeGBrain(root: URL, sourcePath: String, log: URL) throws -> URL {
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let script = bin.appendingPathComponent("gbrain", isDirectory: false)
        let scriptContent = """
        #!/bin/sh
        echo "$@" >> '\(shellSingleQuoted(log.path))'
        if [ "$1" = "doctor" ]; then
          echo '{"ok":true}'
          exit 0
        fi
        if [ "$1" = "sources" ] && [ "$2" = "current" ]; then
          echo '{"source_id":"brain"}'
          exit 0
        fi
        if [ "$1" = "sources" ] && [ "$2" = "list" ]; then
          echo '{"sources":[{"id":"brain","local_path":"\(jsonEscaped(sourcePath))"}]}'
          exit 0
        fi
        exit 0
        """
        try scriptContent.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    private func shellSingleQuoted(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "'\\''")
    }

    private func jsonEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZebraOnboardingChecklistStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
