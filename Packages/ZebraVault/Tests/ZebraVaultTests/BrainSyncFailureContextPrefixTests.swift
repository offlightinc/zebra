import Foundation
import XCTest
@testable import ZebraVault

final class BrainSyncFailureContextPrefixTests: XCTestCase {
    func testBuildRedactsCredentialUserInfoFromOriginRemote() throws {
        let repo = try makeGitRepo()
        try runGit(
            [
                "remote", "set-url", "origin",
                "https://x-access-token:ghp_secretToken123@github.com/offlightinc/brain-offlight.git",
            ],
            cwd: repo
        )

        let output = BrainSyncFailureContextPrefix.build(
            vaultPath: repo.path,
            reason: .authExpired,
            rawReasonId: nil,
            detail: "authentication failed",
            failedAt: nil
        )

        XCTAssertFalse(output.contains("ghp_secretToken123"))
        XCTAssertFalse(output.contains("x-access-token"))
        XCTAssertTrue(output.contains("Origin: https://github.com/offlightinc/brain-offlight.git"))
    }

    func testBuildCapsLargeContextByUTF8Bytes() {
        let output = BrainSyncFailureContextPrefix.build(
            vaultPath: "/tmp/missing-\(UUID().uuidString)",
            reason: .unknown,
            rawReasonId: String(repeating: "x", count: 100_000),
            detail: "unknown failure",
            failedAt: nil
        )

        XCTAssertLessThanOrEqual(output.utf8.count, 24_000)
        XCTAssertTrue(output.hasSuffix("*** truncated to stay under argv limit ***"))
    }

    func testBuildReferencesGitStatusInsteadOfInliningLargeStatus() throws {
        let repo = try makeGitRepo()
        for index in 0..<140 {
            let fileName = "상태-\(index)-\(String(repeating: "가", count: 50)).md"
            try "x\n".write(
                to: repo.appendingPathComponent(fileName),
                atomically: true,
                encoding: .utf8
            )
        }

        let output = BrainSyncFailureContextPrefix.build(
            vaultPath: repo.path,
            reason: .hookFailed,
            rawReasonId: nil,
            detail: "validation failed",
            failedAt: nil
        )

        XCTAssertLessThanOrEqual(output.utf8.count, 24_000)
        XCTAssertTrue(output.contains("- git status --porcelain"))
        XCTAssertNil(sectionBody(in: output, heading: "=== git status --porcelain ==="))
        XCTAssertFalse(output.contains("상태-0"))
    }

    func testRepoSnapshotOmitsCommitSubject() throws {
        let koreanSubject = "tasks: complete Zebra 이메일 chat pill submit"
        let repo = try makeGitRepo(commitMessage: koreanSubject)

        let output = BrainSyncFailureContextPrefix.build(
            vaultPath: repo.path,
            reason: .hookFailed,
            rawReasonId: nil,
            detail: "validation failed",
            failedAt: nil
        )
        let repoSnapshot = try XCTUnwrap(
            sectionBody(in: output, heading: "=== Repo snapshot ===")
        )

        XCTAssertFalse(repoSnapshot.contains(koreanSubject))
        XCTAssertTrue(repoSnapshot.contains("Local HEAD:"))
        XCTAssertFalse(repoSnapshot.contains("committedAt:"))
        XCTAssertFalse(repoSnapshot.contains("authorEmail:"))
        XCTAssertTrue(repoSnapshot.contains("Ahead/behind (`HEAD...origin/main`): 0 ahead, 0 behind"))
    }

    func testConflictPrefixReferencesFilesAndCommandsWithoutInliningBodies() throws {
        let repo = try makeGitRepo()
        let conflictFile = repo.appendingPathComponent("tasks/conflict-test.md")
        try FileManager.default.createDirectory(
            at: conflictFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try """
        # Conflict

        <<<<<<< local
        local branch body
        =======
        remote branch body
        >>>>>>> remote
        """.write(to: conflictFile, atomically: true, encoding: .utf8)

        let output = BrainSyncFailureContextPrefix.build(
            vaultPath: repo.path,
            reason: .conflict,
            rawReasonId: nil,
            detail: "conflict markers found in tasks/conflict-test.md",
            failedAt: nil
        )

        XCTAssertTrue(output.contains("=== Conflict state ==="))
        XCTAssertTrue(output.contains("Files:"))
        XCTAssertTrue(output.contains("tasks/conflict-test.md"))
        XCTAssertTrue(output.contains("rg -n '^(<<<<<<<|=======|>>>>>>>)' -- '*.md'"))
        XCTAssertEqual(output.components(separatedBy: "git status --porcelain").count - 1, 1)
        XCTAssertEqual(output.components(separatedBy: "rg -n '^(<<<<<<<|=======|>>>>>>>)' -- '*.md'").count - 1, 1)
        XCTAssertFalse(output.contains("=== Conflict inspect commands ==="))
        XCTAssertFalse(output.contains("local branch body"))
        XCTAssertFalse(output.contains("remote branch body"))
    }

    private func makeGitRepo(commitMessage: String = "initial") throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZebraVaultTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }

        try runGit(["init"], cwd: root)
        try runGit(["symbolic-ref", "HEAD", "refs/heads/main"], cwd: root)
        try "# Test\n".write(
            to: root.appendingPathComponent("README.md"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "README.md"], cwd: root)
        try runGit(
            [
                "-c", "user.name=Zebra Tests",
                "-c", "user.email=zebra@example.invalid",
                "commit", "-m", commitMessage,
            ],
            cwd: root
        )
        try runGit(["remote", "add", "origin", root.path], cwd: root)
        try runGit(["update-ref", "refs/remotes/origin/main", "HEAD"], cwd: root)
        return root.standardizedFileURL
    }

    private func runGit(_ args: [String], cwd: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + args
        process.currentDirectoryURL = cwd

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let out = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let description = "git \(args.joined(separator: " ")) failed: \(message)\(out)"
            XCTFail(description)
            throw NSError(
                domain: "BrainSyncFailureContextPrefixTests.git",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: description]
            )
        }
    }

    private func sectionBody(in output: String, heading: String) -> String? {
        guard let headingRange = output.range(of: "\(heading)\n") else { return nil }
        let tail = output[headingRange.upperBound...]
        if let nextRange = tail.range(of: "\n\n===") {
            return String(tail[..<nextRange.lowerBound])
        }
        return String(tail)
    }
}
