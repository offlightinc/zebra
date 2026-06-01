import XCTest
@testable import ZebraVault

final class ZebraAgentLaunchCommandTests: XCTestCase {
    func testCodexOnboardingLaunchStartsInteractiveCliWithoutPrompt() {
        let line = ZebraAgentLaunchCommand.shellStartupLine(
            agent: .codex,
            cwd: "/tmp/work dir",
            systemPrompt: "System context",
            userPrompt: "What is 'next'?"
        )

        XCTAssertEqual(line, "cd '/tmp/work dir' && codex\r")
        XCTAssertFalse(line.contains("System context"))
        XCTAssertFalse(line.contains("What is"))
    }

    func testClaudeOnboardingLaunchStartsInteractiveCliWithoutPrompt() {
        let line = ZebraAgentLaunchCommand.shellStartupLine(
            agent: .claude,
            cwd: "/tmp/work",
            systemPrompt: "Zebra setup",
            userPrompt: "Continue\nnow"
        )

        XCTAssertEqual(
            line,
            "cd '/tmp/work' && claude\r"
        )
        XCTAssertFalse(line.contains("--append-system-prompt"))
        XCTAssertFalse(line.contains("Zebra setup"))
    }

    func testAntigravityOnboardingLaunchStartsInteractiveCliWithoutPrompt() {
        let line = ZebraAgentLaunchCommand.shellStartupLine(
            agent: .antigravity,
            cwd: "/tmp/work",
            systemPrompt: "Zebra setup",
            userPrompt: "Continue"
        )

        XCTAssertEqual(
            line,
            "cd '/tmp/work' && agy\r"
        )
        XCTAssertFalse(line.contains("--prompt-interactive"))
        XCTAssertFalse(line.contains("--add-dir"))
        XCTAssertFalse(line.contains("Zebra setup"))
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

    func testOnboardingStartupCommandRunsScriptWithCwd() {
        let line = ZebraAgentOnboardingStartup.shellStartupLine(
            scriptPath: "/Applications/Zebra.app/Contents/Resources/zebra-agent-onboarding",
            cwd: "/Users/han/zebra phase3"
        )

        XCTAssertEqual(
            line,
            "'/Applications/Zebra.app/Contents/Resources/zebra-agent-onboarding' 'run' '--cwd' '/Users/han/zebra phase3'\n"
        )
    }

    func testOnboardingStartupCommandQuotesSingleQuotes() {
        let line = ZebraAgentOnboardingStartup.shellStartupLine(
            scriptPath: "/tmp/zebra-agent-onboarding",
            cwd: "/Users/han/project/it's-zebra"
        )

        XCTAssertEqual(
            line,
            "'/tmp/zebra-agent-onboarding' 'run' '--cwd' '/Users/han/project/it'\\''s-zebra'\n"
        )
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
