import Foundation

enum SourceOnboardingFakeGBrain {
    static func install(root: URL, sourcePath: String, log: URL) throws -> URL {
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        let pageStore = root.appendingPathComponent("fake-gbrain-pages", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pageStore, withIntermediateDirectories: true)
        let script = bin.appendingPathComponent("gbrain", isDirectory: false)
        let content = """
        #!/bin/sh
        echo "$@" >> '\(shellQuote(log.path))'
        if [ "$1" = "doctor" ]; then
          echo '{"ok":true}'
          exit 0
        fi
        if [ "$1" = "sources" ] && [ "$2" = "current" ]; then
          echo '{"source_id":"brain","local_path":"\(jsonEscape(sourcePath))"}'
          exit 0
        fi
        if [ "$1" = "import" ]; then
          staging="$2"
          find "$staging" -type f -name '*.md' -exec cp {} '\(shellQuote(pageStore.path))/' \\;
          count=$(find "$staging" -type f -name '*.md' | wc -l | tr -d ' ')
          printf '{"status":"success","imported":%s,"skipped":0,"errors":0}\n' "$count"
          exit 0
        fi
        if [ "$1" = "put" ]; then
          slug="$2"
          key=$(printf '%s' "$slug" | shasum -a 256 | awk '{print $1}')
          cat > '\(shellQuote(pageStore.path))/'"$key.md"
          echo '{"ok":true}'
          exit 0
        fi
        if [ "$1" = "get" ]; then
          slug="$2"
          match=$(grep -l -F -m 1 "slug: $slug" '\(shellQuote(pageStore.path))/'*.md 2>/dev/null | head -n 1 || true)
          [ -n "$match" ] || exit 4
          cat "$match"
          exit 0
        fi
        if [ "$1" = "sources" ] && [ "$2" = "list" ]; then
          echo '{"sources":[{"id":"brain","local_path":"\(jsonEscape(sourcePath))"}]}'
          exit 0
        fi
        exit 2
        """
        try content.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    static func writeCompletedState(
        to stateURL: URL,
        vaultPath: String,
        executablePath: String,
        sourceRepoPath: String? = nil
    ) throws {
        let targetKey = "vault:\(vaultPath)"
        let timestamp = "2026-06-04T00:00:00Z"
        let target: [String: Any] = [
            "vaultPath": vaultPath,
            "sourceId": "brain",
            "gbrainExecutablePath": executablePath,
            "doctorStatus": ["ok": true, "status": "ok"],
            "sourcesCurrentResult": ["ok": true, "sourceId": "brain", "localPath": vaultPath],
            "searchProbeResult": ["ok": true, "status": "not_run"],
            "verifiedAt": timestamp,
            "complete": true,
            "targetResolution": ["method": "user_created_repo", "confirmedAt": timestamp],
            "reasons": [],
        ]
        var state: [String: Any] = [
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
                "targets": [targetKey: target],
            ],
        ]
        if let sourceRepoPath {
            state["activeGBrainBinding"] = [
                "sourceRepoPath": sourceRepoPath,
                "sourceRepoStatus": "existing",
                "gbrainHomePath": sourceRepoPath,
                "confirmedAt": timestamp,
            ]
        }
        try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys])
            .write(to: stateURL, options: .atomic)
    }

    private static func shellQuote(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "'\\''")
    }

    private static func jsonEscape(_ value: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
        let quoted = data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        return String(quoted.dropFirst().dropLast())
    }
}
