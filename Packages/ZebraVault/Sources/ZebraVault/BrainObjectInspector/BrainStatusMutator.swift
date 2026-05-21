import Foundation

/// brain-offlight / gbrain 컨벤션에 맞춰 task/goal 의 status 및 일반
/// property 전이를 한 묶음으로 처리한다. 단순히 frontmatter 한 줄을 고치는
/// 것이 아니라:
///
/// `applyStatusChange` (status 전용):
///   1. frontmatter `status:` 갱신 (newStatusRaw == nil 이면 키 제거)
///   2. frontmatter `updated:` 를 오늘 날짜로 bump
///   3. completed/done 전이 시 `completed:` 부여, 반대 전이 시 제거
///   4. body `## Timeline` 섹션에 status 변경 bullet append
///      (비우기도 "todo → (none)" 형태로 기록)
///
/// `applyPropertyChange` (priority/owner/due 등 일반 필드):
///   1. frontmatter `<field>:` 갱신 (value == nil 이면 키 제거)
///   2. frontmatter `updated:` 를 오늘 날짜로 bump
///   3. body `## Timeline` 섹션에 property 변경 bullet append
///
/// 이로써 inspector pill / sidebar 리스트 등 모든 property 변경 경로가
/// 같은 의미론을 거치게 된다. frontmatter 의 surgical 수정은 기존
/// `BrainFrontmatterWriter` 에 위임하므로 다른 키의 순서/quoting/comment 는
/// 그대로 보존된다.
///
/// Note: `BrainTaskStatus.waiting` 은 picker UI 의 primaryCases 에서 빠져
/// 있어 사용자가 UI 로 진입할 수 없다. 따라서 `waiting_on:` 자동 관리는
/// 의도적으로 다루지 않는다 — 필요한 사용자는 markdown 에서 직접 적는다.
public enum BrainStatusMutator {
    public enum Kind {
        case task
        case goal

        /// Frontmatter 에 `completed: <today>` 를 부여해야 하는 raw value.
        fileprivate var completedRaw: String {
            switch self {
            case .task: return "done"
            case .goal: return "completed"
            }
        }
    }

    public struct Outcome {
        public let newSource: String
        public let didChange: Bool
    }

    /// In-memory 변환. MarkdownPanel 처럼 자체 content snapshot 을 들고
    /// 있는 호출자가 사용. 변경 후 텍스트를 반환할 뿐 disk write 는
    /// 하지 않는다.
    public static func applyStatusChange(
        in source: String,
        kind: Kind,
        oldStatusRaw: String?,
        newStatusRaw: String?,
        today: Date = Date()
    ) -> Outcome {
        // Same value 재적용은 noise 만 남기므로 no-op.
        if oldStatusRaw == newStatusRaw {
            return Outcome(newSource: source, didChange: false)
        }
        // Frontmatter block 이 없는 파일은 brain object 가 아니므로 건드리지
        // 않는다. 호출자는 사전 파싱된 task/goal 에 대해서만 호출하지만
        // 안전망으로 가드.
        guard hasFrontmatterBlock(source) else {
            return Outcome(newSource: source, didChange: false)
        }

        let todayString = isoDate(today)

        var working = source
        working = BrainFrontmatterWriter.setScalar("status", to: newStatusRaw, in: working)
        working = BrainFrontmatterWriter.setScalar("updated", to: todayString, in: working)

        // completed 필드: 새 status 가 완료 raw 면 오늘 날짜 부여, 이전
        // status 가 완료 raw 였고 이제 아니면 제거. 그 외 케이스에서는 사용자가
        // 직접 적은 completed: 값을 건드리지 않는다.
        if newStatusRaw == kind.completedRaw {
            working = BrainFrontmatterWriter.setScalar("completed", to: todayString, in: working)
        } else if oldStatusRaw == kind.completedRaw {
            working = BrainFrontmatterWriter.setScalar("completed", to: nil, in: working)
        }

        working = appendTimelineEntry(
            in: working,
            todayString: todayString,
            field: "status",
            oldValue: oldStatusRaw,
            newValue: newStatusRaw
        )

        return Outcome(newSource: working, didChange: working != source)
    }

    /// 일반 property (priority / owner / reviewer / due / target_date /
    /// review_cadence 등) 변경. status 외의 모든 inline-edit pill 이 이 경로를
    /// 거쳐 frontmatter writeback + `updated:` bump + Timeline bullet 까지
    /// 일관되게 처리. `newValue == nil` 은 키 제거 (예: due 비우기).
    public static func applyPropertyChange(
        in source: String,
        field: String,
        oldValue: String?,
        newValue: String?,
        today: Date = Date()
    ) -> Outcome {
        if oldValue == newValue {
            return Outcome(newSource: source, didChange: false)
        }
        guard hasFrontmatterBlock(source) else {
            return Outcome(newSource: source, didChange: false)
        }
        // 보호: status 는 별도 의미론(`completed:`, kind 분기)을 가지므로
        // 호출자가 잘못 라우팅한 경우 no-op + diagnostic. silent 로 두면
        // 디버깅 단서가 없어 회귀가 잘 안 드러나기 때문에 NSLog 남긴다.
        if field == "status" {
            NSLog("BrainStatusMutator.applyPropertyChange refused field=status — use applyStatusChange for status transitions")
            return Outcome(newSource: source, didChange: false)
        }

        let todayString = isoDate(today)

        var working = source
        working = BrainFrontmatterWriter.setScalar(field, to: newValue, in: working)
        working = BrainFrontmatterWriter.setScalar("updated", to: todayString, in: working)
        working = appendTimelineEntry(
            in: working,
            todayString: todayString,
            field: field,
            oldValue: oldValue,
            newValue: newValue
        )

        return Outcome(newSource: working, didChange: working != source)
    }

    public static func applyPropertyChange(
        at filePath: String,
        field: String,
        oldValue: String?,
        newValue: String?,
        today: Date = Date()
    ) {
        let url = URL(fileURLWithPath: filePath)
        guard let data = try? Data(contentsOf: url),
              let source = String(data: data, encoding: .utf8) else { return }
        let outcome = applyPropertyChange(
            in: source,
            field: field,
            oldValue: oldValue,
            newValue: newValue,
            today: today
        )
        guard outcome.didChange,
              let newData = outcome.newSource.data(using: .utf8) else { return }
        try? newData.write(to: url, options: .atomic)
    }

    /// File-IO 래퍼. Sidebar 등 panel 외부 호출자용. 실패는 silent no-op
    /// (`BrainFrontmatterWriter.applyScalar` 와 동일 정책).
    public static func applyStatusChange(
        at filePath: String,
        kind: Kind,
        oldStatusRaw: String?,
        newStatusRaw: String?,
        today: Date = Date()
    ) {
        let url = URL(fileURLWithPath: filePath)
        guard let data = try? Data(contentsOf: url),
              let source = String(data: data, encoding: .utf8) else { return }
        let outcome = applyStatusChange(
            in: source,
            kind: kind,
            oldStatusRaw: oldStatusRaw,
            newStatusRaw: newStatusRaw,
            today: today
        )
        guard outcome.didChange,
              let newData = outcome.newSource.data(using: .utf8) else { return }
        try? newData.write(to: url, options: .atomic)
    }

    // MARK: - Helpers

    private static func isoDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f.string(from: date)
    }

    private static func detectNewline(in source: String) -> String {
        return source.contains("\r\n") ? "\r\n" : "\n"
    }

    private static func hasFrontmatterBlock(_ source: String) -> Bool {
        let newline = detectNewline(in: source)
        let lines = source.components(separatedBy: newline)
        guard let first = lines.first,
              first.trimmingCharacters(in: .whitespaces) == "---" else {
            return false
        }
        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                return true
            }
        }
        return false
    }

    private static func appendTimelineEntry(
        in source: String,
        todayString: String,
        field: String,
        oldValue: String?,
        newValue: String?
    ) -> String {
        let oldDisplay = oldValue.map { $0.isEmpty ? "(empty)" : $0 } ?? "(none)"
        let newDisplay = newValue.map { $0.isEmpty ? "(empty)" : $0 } ?? "(none)"
        let bullet = "- **\(todayString)** | \(field): \(oldDisplay) → \(newDisplay) — \(field) changed in Zebra."

        let newline = detectNewline(in: source)
        var lines = source.components(separatedBy: newline)

        // `## Timeline` 헤더 위치 검색 (depth 정확히 2, case-insensitive).
        var headingIndex: Int? = nil
        for i in 0..<lines.count where isTimelineHeading(lines[i]) {
            headingIndex = i
            break
        }

        if let heading = headingIndex {
            // Timeline 섹션 끝: 다음 `## ` 헤더 또는 EOF.
            var sectionEnd = lines.count
            if heading + 1 < lines.count {
                for i in (heading + 1)..<lines.count {
                    let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("## ") || trimmed == "##" {
                        sectionEnd = i
                        break
                    }
                }
            }
            // 섹션 안의 마지막 비어있지 않은 줄 다음에 삽입 (오름차순 timeline
            // 정책 — 기존 brain-offlight task 파일들과 동일 패턴).
            var insertAt = sectionEnd
            while insertAt > heading + 1 {
                let trimmed = lines[insertAt - 1].trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    insertAt -= 1
                } else {
                    break
                }
            }
            lines.insert(bullet, at: insertAt)
            return lines.joined(separator: newline)
        }

        // Timeline 섹션 부재 — 파일 끝에 새 섹션 생성. 파일이 newline 으로
        // 끝나는지 보존.
        let hadTrailingNewline = source.hasSuffix(newline)
        var result = source
        if !hadTrailingNewline {
            result += newline
        }
        // 새 섹션 앞에 빈 줄 확보.
        if !result.hasSuffix(newline + newline) {
            result += newline
        }
        result += "## Timeline" + newline + newline + bullet
        if hadTrailingNewline {
            result += newline
        }
        return result
    }

    private static func isTimelineHeading(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("## ") else { return false }
        let rest = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
        return rest.caseInsensitiveCompare("Timeline") == .orderedSame
    }
}
