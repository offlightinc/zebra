import Foundation

/// Conflict 가 났을 때 agent terminal 에 prompt prefix 로 흘려보낼 컨텍스트.
/// ChatPill 의 `MarkdownChatPillContextPrefix` 와 같은 결로, advisory + 데이터를
/// 한 덩어리 string 으로 묶어서 agent CLI 의 첫 argv 로 넘긴다.
///
/// 책임:
/// - `git status --porcelain` 으로 UU 마커 파일 추출
/// - `git rev-parse origin/main` 으로 local/remote HEAD SHA + commit message
/// - 각 conflict 파일을 raw 로 read 해서 conflict marker section (그리고 약간의
///   주변 context) 만 발췌
/// - 위를 advisory prose + 데이터 블록으로 직렬화
///
/// agent 가 사용자와 자연어로 대화하며 충돌 해결. 4 specific resolution choices
/// (force-push / stash+pull / auto-merge / editor) 는 prefix 끝에 옵션 카탈로그로
/// 보여주고, 실제 선택은 agent ↔ 사용자 대화에서 결정.
public enum BrainSyncConflictContextPrefix {
    /// argv 한계 (macOS ~256KB) 안전망. ChatPill 의 email prefix 와 같은 cap.
    private static let totalByteBudget = 180_000

    /// `vaultPath` 의 conflict 상태를 읽어서 agent prefix string 을 build.
    /// 실패 (vault 가 git repo 아님 / 명령 실패 등) 시 minimal prefix 반환 — agent
    /// 가 빈 손으로 시작하더라도 사용자 자연어로 진행 가능.
    public static func build(vaultPath: String) -> String {
        var sections: [String] = []
        sections.append(advisoryLine(vaultPath: vaultPath))
        sections.append(commonAdvisoryLine)

        if let headBlock = headBlock(vaultPath: vaultPath) {
            sections.append(headBlock)
        }

        let conflictFiles = listConflictFiles(vaultPath: vaultPath)
        if !conflictFiles.isEmpty {
            sections.append(conflictModeNote(vaultPath: vaultPath))
            sections.append(filesListBlock(conflictFiles))
            sections.append(perFileExcerptsBlock(vaultPath: vaultPath, files: conflictFiles))
        } else {
            sections.append("(No `UU` markers found in `git status --porcelain` and no working-tree .md with conflict markers either. This conflict reason may be detected from stderr only; check `git pull --rebase` output or `git diff` manually.)")
        }

        sections.append(resolutionCatalog)

        let combined = sections.joined(separator: "\n\n")
        if combined.utf8.count <= totalByteBudget {
            return combined
        }
        // Cap to budget — argv 한계 안전망. tail truncation 이 자연스러움 (앞쪽이
        // advisory + status 라 더 중요).
        let truncated = String(combined.prefix(totalByteBudget))
        return truncated + "\n\n*** truncated to stay under argv limit ***"
    }

    // MARK: - Advisory templates

    private static func advisoryLine(vaultPath: String) -> String {
        "This terminal opened on top of a brain-sync conflict at `\(vaultPath)`. The vault git repo has divergent commits between local HEAD and `origin/main`, with conflict markers in one or more `.md` files. Your job is to help the user understand the conflict and pick a resolution path."
    }

    private static let commonAdvisoryLine =
        "For tracking down related material, b-brain's `search` / `query` / `get` tend to surface backlinks and compiled_truth that raw grep misses, and leaving a `[Source: …, YYYY-MM-DD]` citation alongside backlinks when writing new facts keeps the graph alive across sessions."

    private static let resolutionCatalog = """
    === Resolution options (offer the user a choice, but let them pick) ===

    1. Keep local — discard remote, force-push.
       Command shape: `git push --force-with-lease`. Destructive to remote, only when the user is certain remote changes should be dropped.

    2. Accept remote — stash local, pull --rebase, drop stash.
       Command shape: `git stash && git pull --rebase && git stash drop`. Local edits move aside; remote becomes source of truth.

    3. Merge both — semantic merge.
       Read both sides, propose a combined version that captures both intents (e.g. "DAU 50 → 100명 (stretch)" for a goal). Apply with `git checkout --theirs/--ours` per hunk, or edit the file directly to remove markers.

    4. Open in editor — leave markers, let user edit by hand.
       The conflict markers (`<<<<<<<` / `=======` / `>>>>>>>`) stay in the file; user resolves manually and runs `git add <file> && git rebase --continue` (or commits).

    Ask the user which path they want before running anything destructive (1) or rebasing (2). Option 3 is the agent's strength — propose the merged version in plain language first, get confirmation, then apply.
    """

    // MARK: - Data collection

    private static func headBlock(vaultPath: String) -> String? {
        guard let local = runGit(["rev-parse", "--short", "HEAD"], cwd: vaultPath) else { return nil }
        let localMsg = runGit(["log", "-1", "--format=%s · %ar", "HEAD"], cwd: vaultPath) ?? ""
        let remote = runGit(["rev-parse", "--short", "origin/main"], cwd: vaultPath) ?? "(unknown)"
        let remoteMsg = runGit(["log", "-1", "--format=%s · %ar · %an", "origin/main"], cwd: vaultPath) ?? ""
        return "=== HEAD vs origin/main ===\nLocal  HEAD: \(local) — \(localMsg)\nRemote HEAD: \(remote) — \(remoteMsg)"
    }

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

    /// 두 modes 구분 — agent 가 "지금 active rebase/merge 중인지" vs "워킹트리에
    /// marker 잔재만 있는지" 알아야 어떻게 풀지 결정 가능 (rebase 중이면 `git
    /// rebase --continue/--abort` 가 필요, 잔재면 사용자가 직접 marker 만 제거하면 됨).
    private static func conflictModeNote(vaultPath: String) -> String {
        let gitDir = (vaultPath as NSString).appendingPathComponent(".git")
        for marker in ["rebase-merge", "rebase-apply", "MERGE_HEAD", "CHERRY_PICK_HEAD"] {
            let path = (gitDir as NSString).appendingPathComponent(marker)
            if FileManager.default.fileExists(atPath: path) {
                return "=== Conflict mode: active rebase/merge ===\nA `\(marker)` state directory exists under `.git/`. After resolving markers, the user (or you on their behalf) must run `git add <files>` and either `git rebase --continue` or `git commit` to finish the rebase/merge."
            }
        }
        return "=== Conflict mode: marker residue (no active rebase/merge) ===\nNo `.git/rebase-*` or `.git/MERGE_HEAD` state directory found. The conflict markers below are residue in the working tree — possibly from a prior unfinished merge, a manual marker insert, or an external conflict. Removing the markers and committing is enough; no `git rebase --continue` needed."
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

    private static func filesListBlock(_ files: [String]) -> String {
        var s = "=== Conflicting files (\(files.count)) ===\n"
        for f in files {
            s += "- \(f)\n"
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func perFileExcerptsBlock(vaultPath: String, files: [String]) -> String {
        var sections: [String] = ["=== Conflict marker excerpts ===\nFiles below are the raw working-tree contents with conflict markers in place. Each file is included up to a per-file char cap; the agent can ask the user to share more if a marker section is truncated."]
        let perFileCap = 8_000   // 한 파일당 char 캡. 일반 markdown 은 한참 못 미친다.
        for file in files {
            let absolute = (vaultPath as NSString).appendingPathComponent(file)
            guard let raw = try? String(contentsOf: URL(fileURLWithPath: absolute), encoding: .utf8) else {
                sections.append("--- \(file) ---\n(failed to read file)")
                continue
            }
            let content: String
            if raw.count > perFileCap {
                content = String(raw.prefix(perFileCap)) + "\n*** file truncated at \(perFileCap) chars ***"
            } else {
                content = raw
            }
            sections.append("--- \(file) ---\n\(content)")
        }
        return sections.joined(separator: "\n\n")
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
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = (try? stdout.fileHandleForReading.readToEnd()) ?? Data()
        let raw = String(data: data, encoding: .utf8) ?? ""
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
