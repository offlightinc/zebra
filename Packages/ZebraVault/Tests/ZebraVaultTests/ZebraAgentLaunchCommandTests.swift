import XCTest
@testable import ZebraVault

final class ZebraAgentLaunchCommandTests: XCTestCase {
    func testCodexLaunchIncludesCwdAndQuotedPrompt() {
        let line = ZebraAgentLaunchCommand.shellStartupLine(
            agent: .codex,
            cwd: "/tmp/work dir",
            systemPrompt: "System context",
            userPrompt: "What is 'next'?"
        )

        XCTAssertTrue(line.contains("cd '/tmp/work dir' && codex -C '/tmp/work dir'"))
        XCTAssertTrue(line.contains("'System context\n\nWhat is '\\''next'\\''?'"))
    }

    func testClaudeLaunchUsesAppendSystemPrompt() {
        let line = ZebraAgentLaunchCommand.shellStartupLine(
            agent: .claude,
            cwd: "/tmp/work",
            systemPrompt: "Zebra setup",
            userPrompt: "Continue\nnow"
        )

        XCTAssertEqual(
            line,
            "cd '/tmp/work' && claude --append-system-prompt 'Zebra setup' 'Continue now'\r"
        )
    }

    func testAntigravityLaunchUsesPromptAndCwdFlags() {
        let line = ZebraAgentLaunchCommand.shellStartupLine(
            agent: .antigravity,
            cwd: "/tmp/work",
            systemPrompt: "Zebra setup",
            userPrompt: "Continue"
        )

        XCTAssertEqual(
            line,
            "cd '/tmp/work' && agy -p 'Zebra setup\n\nContinue' --cwd '/tmp/work'\r"
        )
    }

    func testChatPillAntigravityLaunchUsesAgyPromptAndCwdFlags() throws {
        let cwd = try makeTemporaryDirectory()

        let line = MarkdownChatPillCommand.shellStartupLine(
            agent: .antigravity,
            markdownFilePath: nil,
            surface: .fallback(typeLabel: "general"),
            userPrompt: "Check this",
            launchDirectory: cwd.path
        )

        XCTAssertTrue(line.contains("cd '\(cwd.path)' && agy -p '"))
        XCTAssertTrue(line.contains("--cwd '\(cwd.path)'"))
        XCTAssertFalse(line.contains("gemini"))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZebraAgentLaunchCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url.standardizedFileURL
    }
}
