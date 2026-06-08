import Foundation

/// Stages long programmatic terminal startup commands into a temporary shell
/// script so only a short `source '<path>'` line is injected into the PTY.
///
/// Programmatic injection writes bytes into the PTY master; the kernel line
/// discipline queues them for the slave (the shell). BSD/macOS caps that input
/// queue at `TTYHOG` (1024 bytes). While the shell is still starting up and not
/// yet draining input, anything past that cap is silently discarded. Long
/// onboarding commands — full agent prompts, the multi-step GBrain bootstrap
/// chain — routinely exceed 1 KB and get truncated mid-command.
///
/// Staging keeps the injected line tiny (well under the cap) regardless of how
/// long the underlying command grows: the shell reads the short `source` line,
/// then runs the full command from disk where no PTY-queue cap applies.
public enum ZebraTerminalStartupStaging {
    /// Commands at or below this byte budget inject inline. Longer ones stage to
    /// a file. Kept comfortably under `TTYHOG` (1024) to leave headroom for any
    /// bytes already queued ahead of this command.
    static let inlineByteBudget = 800

    /// Returns a startup line safe to inject into a freshly created terminal.
    ///
    /// Short commands are returned unchanged. Commands whose byte count exceeds
    /// `inlineByteBudget` are written to a temporary script and replaced with a
    /// short `source '<path>'` line that preserves the original trailing return.
    /// If the script cannot be written, the original line is returned unchanged
    /// (the command may truncate, but behavior is no worse than before staging).
    public static func stage(
        startupLine: String,
        fileManager: FileManager = .default,
        directory: URL? = nil
    ) -> String {
        let (command, lineEnding) = splitTrailingNewline(startupLine)
        guard command.utf8.count > inlineByteBudget else { return startupLine }
        guard let scriptURL = writeScript(
            command: command,
            fileManager: fileManager,
            directory: directory
        ) else {
            return startupLine
        }
        return "source \(shellQuote(scriptURL.path))\(lineEnding)"
    }

    private static func splitTrailingNewline(
        _ line: String
    ) -> (command: String, lineEnding: String) {
        // "\r\n" is a single Swift Character (grapheme cluster), so a lone
        // dropLast() removes the whole CRLF — same logic the injection-side
        // events plan uses.
        if line.hasSuffix("\r\n") || line.hasSuffix("\r") || line.hasSuffix("\n") {
            return (String(line.dropLast()), "\r")
        }
        return (line, "")
    }

    private static func writeScript(
        command: String,
        fileManager: FileManager,
        directory: URL?
    ) -> URL? {
        let baseDirectory = directory ?? fileManager.temporaryDirectory
            .appendingPathComponent("zebra-startup-lines", isDirectory: true)
        do {
            try fileManager.createDirectory(
                at: baseDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            return nil
        }
        let scriptURL = baseDirectory.appendingPathComponent(
            "startup-\(UUID().uuidString).sh",
            isDirectory: false
        )
        // Trailing newline so the final `&&`-chained command runs even though the
        // injected return is stripped from the staged command text.
        let contents = command + "\n"
        do {
            try contents.write(to: scriptURL, atomically: true, encoding: .utf8)
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: scriptURL.path
            )
        } catch {
            return nil
        }
        return scriptURL
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
