import SwiftUI

enum GoalDuePillKind: Equatable {
    case neutral
    case warn
    case danger
}

struct GoalDueDescriptor: Equatable {
    let label: String
    let kind: GoalDuePillKind
}

struct GoalOutlineRow: View, Equatable {
    let displayName: String
    let depth: Int
    let hasChildren: Bool
    let expanded: Bool
    let isCompleted: Bool
    let isSelected: Bool
    let onChevronTap: () -> Void
    let onRowTap: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.displayName == rhs.displayName
            && lhs.depth == rhs.depth
            && lhs.hasChildren == rhs.hasChildren
            && lhs.expanded == rhs.expanded
            && lhs.isCompleted == rhs.isCompleted
            && lhs.isSelected == rhs.isSelected
    }

    var body: some View {
        Button(action: onRowTap) {
            HStack(spacing: 0) {
                ZStack {
                    if hasChildren {
                        Button(action: onChevronTap) {
                            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                                .frame(width: GoalsDesignTokens.outlineChevronColumnWidth, height: GoalsDesignTokens.rowHeight)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear
                            .frame(width: GoalsDesignTokens.outlineChevronColumnWidth, height: GoalsDesignTokens.rowHeight)
                    }
                }
                Text(displayName)
                    .font(.system(size: GoalsDesignTokens.rowFontSize, weight: .regular))
                    .foregroundStyle(isCompleted ? Color(nsColor: .secondaryLabelColor) : Color(nsColor: .labelColor))
                    .strikethrough(isCompleted, color: Color(nsColor: .secondaryLabelColor))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.leading, GoalsDesignTokens.rowHorizontalPadding + CGFloat(depth) * GoalsDesignTokens.outlineIndentPerLevel)
            .padding(.trailing, GoalsDesignTokens.rowHorizontalPadding)
            .frame(height: GoalsDesignTokens.rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Color.accentColor.opacity(GoalsDesignTokens.selectionAlpha) : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("VerticalTabsSidebar.Goals.outlineRow")
    }
}

struct GoalCadenceRow: View, Equatable {
    let displayName: String
    let due: GoalDueDescriptor
    let isCompleted: Bool
    let isSelected: Bool
    let onTap: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.displayName == rhs.displayName
            && lhs.due == rhs.due
            && lhs.isCompleted == rhs.isCompleted
            && lhs.isSelected == rhs.isSelected
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                goalRowTitle(displayName, isCompleted: isCompleted)
                Spacer(minLength: 0)
                goalDuePill(due)
            }
            .modifier(GoalFlatRowChrome(isSelected: isSelected))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("VerticalTabsSidebar.Goals.cadenceRow")
    }
}

struct GoalStatusRow: View, Equatable {
    let displayName: String
    let milestoneDone: Int
    let milestoneTotal: Int
    let isCompleted: Bool
    let isSelected: Bool
    let onTap: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.displayName == rhs.displayName
            && lhs.milestoneDone == rhs.milestoneDone
            && lhs.milestoneTotal == rhs.milestoneTotal
            && lhs.isCompleted == rhs.isCompleted
            && lhs.isSelected == rhs.isSelected
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                goalRowTitle(displayName, isCompleted: isCompleted)
                Spacer(minLength: 0)
                Text("\(milestoneDone)/\(milestoneTotal)")
                    .font(.system(size: GoalsDesignTokens.metaFontSize, weight: .regular))
                    .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                    .monospacedDigit()
            }
            .modifier(GoalFlatRowChrome(isSelected: isSelected))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("VerticalTabsSidebar.Goals.statusRow")
    }
}

// Shared row title + flat-row chrome used by GoalCadenceRow and GoalStatusRow.
// Keep these file-private so they stay coupled to the row consumers above.

@ViewBuilder
private func goalRowTitle(_ displayName: String, isCompleted: Bool) -> some View {
    Text(displayName)
        .font(.system(size: GoalsDesignTokens.rowFontSize, weight: .regular))
        .foregroundStyle(isCompleted ? Color(nsColor: .secondaryLabelColor) : Color(nsColor: .labelColor))
        .strikethrough(isCompleted, color: Color(nsColor: .secondaryLabelColor))
        .lineLimit(1)
        .truncationMode(.tail)
}

@ViewBuilder
private func goalDuePill(_ due: GoalDueDescriptor) -> some View {
    let (fg, bg) = goalDuePillColors(for: due.kind)
    Text(due.label)
        .font(.system(size: GoalsDesignTokens.metaFontSize, weight: .regular))
        .foregroundStyle(fg)
        .padding(.horizontal, GoalsDesignTokens.metaPillHorizontalPadding)
        .padding(.vertical, GoalsDesignTokens.metaPillVerticalPadding)
        .background(
            RoundedRectangle(cornerRadius: GoalsDesignTokens.metaPillCornerRadius, style: .continuous)
                .fill(bg)
        )
}

private func goalDuePillColors(for kind: GoalDuePillKind) -> (Color, Color) {
    switch kind {
    case .neutral:
        return (Color(nsColor: .secondaryLabelColor), Color(nsColor: .tertiarySystemFill))
    case .warn:
        return (Color(nsColor: .systemOrange), Color(nsColor: .systemOrange).opacity(0.18))
    case .danger:
        return (Color(nsColor: .systemRed), Color(nsColor: .systemRed).opacity(0.18))
    }
}

private struct GoalFlatRowChrome: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        content
            .padding(.leading, GoalsDesignTokens.rowHorizontalPadding + GoalsDesignTokens.flatRowLeadingInset)
            .padding(.trailing, GoalsDesignTokens.rowHorizontalPadding)
            .frame(height: GoalsDesignTokens.rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Color.accentColor.opacity(GoalsDesignTokens.selectionAlpha) : Color.clear
            )
            .contentShape(Rectangle())
    }
}

struct GoalGroupHeader: View, Equatable {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: GoalsDesignTokens.groupHeaderCountSpacing) {
            Text(title)
                .font(.system(size: GoalsDesignTokens.groupHeaderFontSize, weight: .semibold))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .textCase(.uppercase)
            Text("\(count)")
                .font(.system(size: GoalsDesignTokens.groupHeaderFontSize, weight: .semibold))
                .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                .monospacedDigit()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, GoalsDesignTokens.groupHeaderHorizontalPadding)
        .padding(.top, GoalsDesignTokens.groupHeaderTopPadding)
        .padding(.bottom, GoalsDesignTokens.groupHeaderBottomPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum GoalDueLabelBuilder {
    static func descriptor(for date: Date?, now: Date = Date()) -> GoalDueDescriptor {
        guard let date else {
            return GoalDueDescriptor(
                label: String(localized: "verticalTabsSidebar.goals.due.noDue", defaultValue: "no due"),
                kind: .neutral
            )
        }
        let cal = Calendar(identifier: .gregorian)
        let startOfToday = cal.startOfDay(for: now)
        let startOfTarget = cal.startOfDay(for: date)
        let days = cal.dateComponents([.day], from: startOfToday, to: startOfTarget).day ?? 0
        if days < 0 {
            let over = -days
            return GoalDueDescriptor(label: "\(over)d over", kind: .danger)
        }
        if days == 0 {
            return GoalDueDescriptor(
                label: String(localized: "verticalTabsSidebar.goals.due.today", defaultValue: "today"),
                kind: .warn
            )
        }
        if days <= 60 {
            let kind: GoalDuePillKind = days <= 14 ? .warn : .neutral
            return GoalDueDescriptor(label: "in \(days)d", kind: kind)
        }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "MMM d"
        return GoalDueDescriptor(label: df.string(from: date), kind: .neutral)
    }
}
