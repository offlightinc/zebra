import Foundation

public struct MarkdownFileEntry: Identifiable, Hashable, Sendable {
    public let absolutePath: String
    public let displayName: String
    public let relativeParentPath: String

    public var id: String { absolutePath }
}

public struct MarkdownTreeFolder: Identifiable, Hashable, Sendable {
    public let folderPath: String      // "" = root, otherwise "docs/" or "docs/api/"
    public let displayName: String     // leaf segment, e.g., "api" (empty for root)
    public let subfolders: [MarkdownTreeFolder]
    public let files: [MarkdownFileEntry]

    public var id: String { folderPath.isEmpty ? "__root__" : folderPath }

    public static func build(from entries: [MarkdownFileEntry]) -> MarkdownTreeFolder {
        let normalized = entries.map { entry -> MarkdownFileEntry in
            entry
        }
        return buildNode(entries: normalized, folderPath: "")
    }

    private static func buildNode(entries: [MarkdownFileEntry], folderPath: String) -> MarkdownTreeFolder {
        let normalizedFolderPath = folderPath
        let directFiles = entries.filter { $0.relativeParentPath == normalizedFolderPath }
        var subfolderNames: Set<String> = []
        for entry in entries {
            guard entry.relativeParentPath.hasPrefix(normalizedFolderPath),
                  entry.relativeParentPath != normalizedFolderPath else { continue }
            let remainder = String(entry.relativeParentPath.dropFirst(normalizedFolderPath.count))
            if let firstSegment = remainder.split(separator: "/").first {
                subfolderNames.insert(String(firstSegment))
            }
        }
        let sortedSubNames = subfolderNames.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        let subfolders = sortedSubNames.map { name in
            buildNode(entries: entries, folderPath: normalizedFolderPath + name + "/")
        }
        let sortedFiles = directFiles.sorted { lhs, rhs in
            lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
        let leafName: String
        if folderPath.isEmpty {
            leafName = ""
        } else {
            let trimmed = folderPath.hasSuffix("/") ? String(folderPath.dropLast()) : folderPath
            leafName = (trimmed as NSString).lastPathComponent
        }
        return MarkdownTreeFolder(
            folderPath: folderPath,
            displayName: leafName,
            subfolders: subfolders,
            files: sortedFiles
        )
    }
}
