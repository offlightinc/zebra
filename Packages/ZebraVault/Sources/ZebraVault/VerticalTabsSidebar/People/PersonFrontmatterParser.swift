import Foundation

enum PersonFrontmatterParser {
    /// Parses a `.md` file's YAML frontmatter into a PersonEntry.
    /// Reads only the head of the file (frontmatter is at the top).
    /// Returns nil if the file has no frontmatter or `type: person` marker.
    static func parse(filePath: String, headBytes: Int = FrontmatterUtils.defaultHeadBytes) -> PersonEntry? {
        guard let head = FrontmatterUtils.readHead(path: filePath, bytes: headBytes) else { return nil }
        guard let raw = FrontmatterUtils.extractFrontmatterBlock(from: head) else { return nil }
        let kv = FrontmatterUtils.parseFlatKeyValues(raw)
        guard kv["type"]?.trimmedUnquoted.lowercased() == "person" else { return nil }

        let stem = ((filePath as NSString).lastPathComponent as NSString).deletingPathExtension
        let title = kv["title"]?.trimmedUnquoted
        let displayName = (title?.isEmpty == false) ? title! : stem

        return PersonEntry(
            absolutePath: filePath,
            slug: stem,
            displayName: displayName
        )
    }
}
