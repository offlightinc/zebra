import Foundation

/// Conflict-specific references for the generic brain-sync failure prefix.
/// Keep this compact: include mode, paths, and commands, not file bodies.
public enum BrainSyncConflictContextPrefix {
    private static let totalByteBudget = 12_000

    public static func build(vaultPath: String) -> String {
        var sections: [String] = []

        let conflictFiles = listConflictFiles(vaultPath: vaultPath)
        if !conflictFiles.isEmpty {
            sections.append(conflictStateBlock(vaultPath: vaultPath, files: conflictFiles))
        } else {
            sections.append("(No `UU` markers found in `git status --porcelain` and no working-tree .md with conflict markers either. This conflict reason may be detected from stderr only; check `git pull --rebase` output or `git diff` manually.)")
        }

        let combined = sections.joined(separator: "\n\n")
        if combined.utf8.count <= totalByteBudget {
            return combined
        }
        let marker = "\n\n*** truncated to stay under argv limit ***"
        let contentBudget = max(0, totalByteBudget - marker.utf8.count)
        return utf8Prefix(combined, byteBudget: contentBudget) + marker
    }

    // MARK: - Data collection

    private static func listConflictFiles(vaultPath: String) -> [String] {
        var files: [String] = []
        // Path 1: git status --porcelain 의 UU 마커 — 진짜 active git merge conflict.
        // porcelain v1: 2-char status code + space + path. UU = both modified.
        // AA/DD/AU/UA/UD/DU 도 conflict variant 라 묶어서 "U" 가 들어가면 다 잡는다.
        if let status = runGit(["status", "--porcelain"], cwd: vaultPath) {
            for line in status.split(separator: "\n") {
                guard line.count > 3 else { continue }
                let code = line.prefix(2)
                if code.contains("U") || code == "AA" || code == "DD" {
                    files.append(String(line.dropFirst(3)))
                }
            }
        }
        // Path 2 fallback: working tree 의 modified/untracked .md 들 중 line-start
        // 가 conflict marker 패턴인 파일. zebra-brain-sync 의 validate_path 가
        // 잡는 케이스 = 외부 git 충돌의 잔재가 워킹트리에 남아있거나, 또는
        // 사용자가 직접 marker 를 입력한 경우. UU 가 0 개면 이 fallback 만.
        if files.isEmpty {
            files = findFilesWithConflictMarkers(vaultPath: vaultPath)
        }
        return files
    }

    private static func conflictStateBlock(vaultPath: String, files: [String]) -> String {
        let gitDir = (vaultPath as NSString).appendingPathComponent(".git")
        for marker in ["rebase-merge", "rebase-apply", "MERGE_HEAD", "CHERRY_PICK_HEAD"] {
            let path = (gitDir as NSString).appendingPathComponent(marker)
            if FileManager.default.fileExists(atPath: path) {
                return conflictStateText(mode: "active git operation marker: \(marker)", files: files)
            }
        }
        return conflictStateText(
            mode: "marker residue only; no active rebase/merge marker found under `.git`",
            files: files
        )
    }

    private static func findFilesWithConflictMarkers(vaultPath: String) -> [String] {
        let ls = runGit(["ls-files", "--modified", "--others", "--exclude-standard"], cwd: vaultPath) ?? ""
        let candidates = ls
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { $0.hasSuffix(".md") }
        var matched: [String] = []
        for relPath in candidates {
            let absolute = (vaultPath as NSString).appendingPathComponent(relPath)
            guard let content = try? String(contentsOf: URL(fileURLWithPath: absolute), encoding: .utf8) else {
                continue
            }
            // zebra-brain-sync 의 validate_path 와 같은 line-start regex 패턴.
            for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
                if line.hasPrefix("<<<<<<<") || line.hasPrefix("=======") || line.hasPrefix(">>>>>>>") {
                    matched.append(relPath)
                    break
                }
            }
        }
        return matched
    }

    private static func conflictStateText(mode: String, files: [String]) -> String {
        let renderedFiles = files.map { "- \(inlineSafe($0))" }.joined(separator: "\n")
        return """
        === Conflict state ===
        Mode: \(mode)
        Files:
        \(renderedFiles)
        """
    }

    // MARK: - git subprocess

    /// `git <args>` 를 `vaultPath` cwd 에서 실행. stdout trim 결과 반환.
    /// 실패 (exit != 0) 또는 launch error 면 nil. zebra 가 brain repo 의
    /// state 를 read-only 로 보는 용도라 throws 없이 best-effort.
    private static func runGit(_ args: [String], cwd: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + args
        process.currentDirectoryURL = URL(fileURLWithPath: cwd, isDirectory: true)

        var env = ProcessInfo.processInfo.environment
        let extraPaths = "/opt/homebrew/bin:/usr/local/bin"
        env["PATH"] = (env["PATH"] ?? "/usr/bin:/bin") + ":" + extraPaths
        process.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return nil
        }
        // pipe 버퍼 fill 시 deadlock 방지 — 두 pipe 동시 drain (`git status` 같은
        // 명령은 보통 작지만 large brain repo + 많은 UU 마커면 64KB 초과 가능).
        let group = DispatchGroup()
        let drainQueue = DispatchQueue(label: "com.zebra.brainsync.git-drain", attributes: .concurrent)
        nonisolated(unsafe) var stdoutData = Data()
        nonisolated(unsafe) var stderrData = Data()
        drainQueue.async(group: group) {
            stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        }
        drainQueue.async(group: group) {
            stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        }
        process.waitUntilExit()
        group.wait()
        _ = stderrData   // captured for symmetry; current callers only use stdout.
        guard process.terminationStatus == 0 else { return nil }
        let raw = String(data: stdoutData, encoding: .utf8) ?? ""
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func inlineSafe(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return value }
        for scalar in trimmed.unicodeScalars {
            if scalar.value < 0x20 || scalar.value > 0x7e {
                return "(contains non-ASCII; inspect with git status --porcelain)"
            }
        }
        return trimmed
    }

    private static func utf8Prefix(_ value: String, byteBudget: Int) -> String {
        guard byteBudget > 0 else { return "" }
        var used = 0
        var result = ""
        result.reserveCapacity(min(value.count, byteBudget))
        for character in value {
            let bytes = String(character).utf8.count
            guard used + bytes <= byteBudget else { break }
            result.append(character)
            used += bytes
        }
        return result
    }
}
