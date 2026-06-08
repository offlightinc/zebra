import XCTest
@testable import ZebraVault

final class ZebraTerminalStartupStagingTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zebra-startup-staging-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
        try super.tearDownWithError()
    }

    func testShortCommandIsReturnedUnchanged() {
        let line = "echo hello\r"
        let staged = ZebraTerminalStartupStaging.stage(
            startupLine: line,
            directory: directory
        )
        XCTAssertEqual(staged, line)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testLongCommandIsStagedToFileAndInjectsShortSourceLine() throws {
        let command = "echo " + String(repeating: "x", count: 2000)
        let line = command + "\r"

        let staged = ZebraTerminalStartupStaging.stage(
            startupLine: line,
            directory: directory
        )

        XCTAssertTrue(staged.hasPrefix("source '"))
        XCTAssertTrue(staged.hasSuffix("'\r"))
        // The injected line must stay well under the kernel PTY input queue cap.
        XCTAssertLessThan(staged.utf8.count, 256)

        let path = try scriptPath(fromSourceLine: staged)
        let contents = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertEqual(contents, command + "\n")
    }

    func testStagedScriptPreservesCRLFAsSingleReturn() throws {
        let command = "printf done " + String(repeating: "y", count: 2000)
        let line = command + "\r\n"

        let staged = ZebraTerminalStartupStaging.stage(
            startupLine: line,
            directory: directory
        )

        XCTAssertTrue(staged.hasSuffix("'\r"))
        XCTAssertFalse(staged.contains("\n"))

        let path = try scriptPath(fromSourceLine: staged)
        let contents = try String(contentsOfFile: path, encoding: .utf8)
        XCTAssertEqual(contents, command + "\n")
    }

    func testStagedScriptHasOwnerOnlyPermissions() throws {
        let command = "echo " + String(repeating: "z", count: 2000)
        let staged = ZebraTerminalStartupStaging.stage(
            startupLine: command + "\r",
            directory: directory
        )
        let path = try scriptPath(fromSourceLine: staged)
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(permissions, 0o600)
    }

    func testSingleQuotesInPathAreEscaped() throws {
        let quotedDirectory = directory
            .appendingPathComponent("o'brien", isDirectory: true)
        let command = "echo " + String(repeating: "q", count: 2000)
        let staged = ZebraTerminalStartupStaging.stage(
            startupLine: command + "\r",
            directory: quotedDirectory
        )
        XCTAssertTrue(staged.contains("'\\''"))
        let path = try scriptPath(fromSourceLine: staged)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    private func scriptPath(fromSourceLine line: String) throws -> String {
        var trimmed = line
        if trimmed.hasSuffix("\r") {
            trimmed.removeLast()
        }
        guard trimmed.hasPrefix("source ") else {
            throw XCTSkip("not a source line: \(line)")
        }
        let quoted = String(trimmed.dropFirst("source ".count))
        // Reverse the shell single-quote escaping used by the staging helper.
        guard quoted.hasPrefix("'"), quoted.hasSuffix("'") else {
            throw XCTSkip("not single-quoted: \(quoted)")
        }
        let inner = String(quoted.dropFirst().dropLast())
        return inner.replacingOccurrences(of: "'\\''", with: "'")
    }
}
