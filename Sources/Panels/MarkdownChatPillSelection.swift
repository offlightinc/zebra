import Foundation

/// A snapshot of the user's text selection inside the markdown body, used to
/// drive the yellow selection chip in the pill and to embed an excerpt /
/// heading hint into the agent's first prompt.
///
/// Designed as a pure value type so the parent (`MarkdownPanelView`) can
/// build/replace/clear instances when its NSTextView selection observer fires,
/// without the pill needing to know about NSTextView at all.
///
/// Split out of `MarkdownChatPill.swift` for the same reason as
/// `MarkdownChatPillCommand`: the pill view file was thousand-lines and
/// folding the pure-data selection model into the same translation unit
/// made it harder to spot semantic bugs.
struct MarkdownChatPillSelection: Equatable {
    /// Whitespace-collapsed, single-line text, truncated to <= 500 chars with
    /// an ellipsis. This is the form we embed in the CLI prompt argument so
    /// the agent gets the excerpt verbatim regardless of original newlines.
    let fullExcerpt: String
    /// Original character count of the raw selection (before truncation /
    /// whitespace collapse). Shown in the chip label as "N chars".
    let chars: Int
    /// Number of newline-separated lines in the raw selection.
    let lines: Int
    /// Nearest preceding markdown heading (`## State`, `### ...`) of the
    /// selection's location in the source — nil when the selection sits
    /// above all headings, or when the heading lookup fails (e.g., the
    /// rendered text doesn't match the source verbatim).
    let heading: String?

    /// Build a snapshot from raw selected text and the panel's source. Returns
    /// nil when the selection is too short (< 3 chars after a whitespace
    /// trim) — matches the mockup's behavior (mouseup with < 3 chars is a
    /// stray click, not a meaningful selection).
    static func capture(rawText: String, in panelContent: String) -> MarkdownChatPillSelection? {
        let collapsed = rawText
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard collapsed.count >= 3 else { return nil }

        let chars = rawText.count
        let lines = rawText
            .components(separatedBy: CharacterSet.newlines)
            .count
        let heading = nearestPrecedingHeading(of: rawText, in: panelContent)
        let excerptCap = 500
        let fullExcerpt = collapsed.count > excerptCap
            ? String(collapsed.prefix(excerptCap - 1)) + "\u{2026}"
            : collapsed
        return .init(
            fullExcerpt: fullExcerpt,
            chars: chars,
            lines: lines,
            heading: heading
        )
    }

    /// Shorter form used in the chip UI (italic quote). The mockup caps the
    /// chip excerpt at 110 chars; the full 500-char form is reserved for the
    /// prompt that actually reaches the agent.
    var displayExcerpt: String {
        let cap = 110
        guard fullExcerpt.count > cap else { return fullExcerpt }
        return String(fullExcerpt.prefix(cap - 2)) + "\u{2026}"
    }

    /// Walk back from the selection's substring start in the source content
    /// to find the most recent `#` / `##` / ... line. Best-effort — if the
    /// rendered selection text doesn't appear verbatim in the source (e.g.,
    /// MarkdownUI stripped emphasis markers) we just return nil and the chip
    /// renders without a heading.
    private static func nearestPrecedingHeading(of selection: String, in content: String) -> String? {
        let trimmedSelection = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSelection.isEmpty,
              let range = content.range(of: trimmedSelection) else { return nil }
        let prefix = content[..<range.lowerBound]
        for line in prefix.split(separator: "\n", omittingEmptySubsequences: false).reversed() {
            let stripped = line.trimmingCharacters(in: .whitespaces)
            guard stripped.hasPrefix("#") else { continue }
            let title = stripped.drop(while: { $0 == "#" })
                .trimmingCharacters(in: .whitespaces)
            if !title.isEmpty { return title }
        }
        return nil
    }
}
