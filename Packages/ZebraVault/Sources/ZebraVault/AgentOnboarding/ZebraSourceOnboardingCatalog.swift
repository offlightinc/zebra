import Foundation

enum ZebraSourceOnboardingCatalog {
    struct SourceDefinition: Equatable, Sendable {
        var id: String
        var displayName: String
        var type: String
        var aliases: [String]
    }

    struct UncatalogedDefinition: Equatable, Sendable {
        var id: String
        var displayName: String
        var aliases: [String]
    }

    struct NormalizationResult: Equatable, Sendable {
        var rawSourceInput: String
        var normalizedSourceList: [String]
        var uncatalogedSources: [ZebraSourceOnboardingState.UncatalogedSource]
        var sourceRows: [String: ZebraSourceOnboardingState.SourceRow]
        var confirmationPrompt: String
    }

    static let supportedSources: [SourceDefinition] = [
        SourceDefinition(
            id: "gmail",
            displayName: "Gmail",
            type: "email",
            aliases: ["gmail", "지메일", "이메일", "email", "메일"]
        ),
        SourceDefinition(
            id: "obsidian",
            displayName: "Obsidian",
            type: "vault",
            aliases: ["obsidian", "옵시디언", "옵시디안", "vault", "볼트"]
        ),
        SourceDefinition(
            id: "imessage",
            displayName: "iMessage",
            type: "messages",
            aliases: ["imessage", "imsg", "아이메세지", "아이메시지", "messages", "message", "문자", "sms"]
        ),
        SourceDefinition(
            id: "notion",
            displayName: "Notion",
            type: "workspace",
            aliases: ["notion", "노션"]
        ),
        SourceDefinition(
            id: "apple-notes",
            displayName: "Apple Notes",
            type: "notes",
            aliases: ["apple notes", "apple note", "애플노트", "애플 노트", "애플 메모", "맥북 메모", "notes", "memo"]
        ),
    ]

    static let uncatalogedSourceHints: [UncatalogedDefinition] = [
        UncatalogedDefinition(
            id: "slack",
            displayName: "Slack",
            aliases: ["slack", "슬랙"]
        ),
        UncatalogedDefinition(
            id: "apple-reminders",
            displayName: "Apple Reminders",
            aliases: ["apple reminders", "apple reminder", "애플 리마인더", "reminders", "reminder"]
        ),
    ]

    static func normalize(rawSourceInput: String) -> NormalizationResult {
        let matches = (
            supportedSources.compactMap { definition -> SourceMatch? in
                earliestMatch(
                    in: rawSourceInput,
                    aliases: definition.aliases,
                    id: definition.id,
                    displayName: definition.displayName,
                    type: definition.type
                )
            }
            + uncatalogedSourceHints.compactMap { definition -> SourceMatch? in
                earliestMatch(
                    in: rawSourceInput,
                    aliases: definition.aliases,
                    id: definition.id,
                    displayName: definition.displayName,
                    type: nil
                )
            }
        )
        .sorted()

        var seenSupportedIDs: Set<String> = []
        var seenUncatalogedIDs: Set<String> = []
        var promptNames: [String] = []
        var normalizedSourceList: [String] = []
        var uncatalogedSources: [ZebraSourceOnboardingState.UncatalogedSource] = []

        for match in matches {
            if match.type != nil {
                guard !seenSupportedIDs.contains(match.id) else { continue }
                seenSupportedIDs.insert(match.id)
                normalizedSourceList.append(match.id)
            } else {
                guard !seenUncatalogedIDs.contains(match.id) else { continue }
                seenUncatalogedIDs.insert(match.id)
                uncatalogedSources.append(
                    ZebraSourceOnboardingState.UncatalogedSource(
                        rawValue: match.rawValue,
                        normalizedValue: match.id,
                        displayName: match.displayName,
                        reason: "not_in_current_catalog"
                    )
                )
            }
            promptNames.append(match.displayName)
        }

        let rows = Dictionary(
            uniqueKeysWithValues: normalizedSourceList.compactMap { id -> (String, ZebraSourceOnboardingState.SourceRow)? in
                guard let definition = supportedSources.first(where: { $0.id == id }) else { return nil }
                return (
                    id,
                    ZebraSourceOnboardingState.SourceRow(
                        id: definition.id,
                        displayName: definition.displayName,
                        type: definition.type,
                        phase: "intake",
                        status: "unchecked",
                        selectionState: "pending_confirmation",
                        updatedAt: nil
                    )
                )
            }
        )

        return NormalizationResult(
            rawSourceInput: rawSourceInput,
            normalizedSourceList: normalizedSourceList,
            uncatalogedSources: uncatalogedSources,
            sourceRows: rows,
            confirmationPrompt: confirmationPrompt(forDisplayNames: promptNames)
        )
    }

    static func displayName(for id: String) -> String {
        supportedSources.first(where: { $0.id == id })?.displayName ?? id
    }

    static func confirmationPrompt(for sourceIDs: [String]) -> String {
        confirmationPrompt(forDisplayNames: sourceIDs.map(displayName(for:)))
    }

    static func confirmationPrompt(forDisplayNames names: [String]) -> String {
        guard !names.isEmpty else {
            return "아직 Zebra가 처리할 수 있는 source를 확인하지 못했습니다. Zebra가 이해해야 할 source를 자유롭게 적어주세요."
        }
        return "\(names.joined(separator: ", "))로 이해했습니다. 맞나요?"
    }

    private static func earliestMatch(
        in input: String,
        aliases: [String],
        id: String,
        displayName: String,
        type: String?
    ) -> SourceMatch? {
        aliases
            .compactMap { alias -> SourceMatch? in
                guard let range = input.range(
                    of: alias,
                    options: [.caseInsensitive, .diacriticInsensitive]
                ) else {
                    return nil
                }
                return SourceMatch(
                    id: id,
                    displayName: displayName,
                    type: type,
                    rawValue: String(input[range]),
                    location: range.lowerBound.utf16Offset(in: input),
                    length: range.upperBound.utf16Offset(in: input) - range.lowerBound.utf16Offset(in: input)
                )
            }
            .min()
    }

    private struct SourceMatch: Comparable {
        var id: String
        var displayName: String
        var type: String?
        var rawValue: String
        var location: Int
        var length: Int

        static func < (lhs: SourceMatch, rhs: SourceMatch) -> Bool {
            if lhs.location != rhs.location {
                return lhs.location < rhs.location
            }
            if lhs.length != rhs.length {
                return lhs.length > rhs.length
            }
            return lhs.id < rhs.id
        }
    }
}
