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

struct GoalOutlineRow: View {
    let displayName: String
    let depth: Int
    let hasChildren: Bool
    let expanded: Bool
    let isCompleted: Bool
    let isSelected: Bool
    let onChevronTap: () -> Void
    let onRowTap: () -> Void

    @State private var rowHover = false

    var body: some View {
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
            goalRowTitle(displayName, isCompleted: isCompleted)
            Spacer(minLength: 0)
        }
        .padding(.leading, GoalsDesignTokens.rowHorizontalPadding + CGFloat(depth) * GoalsDesignTokens.outlineIndentPerLevel)
        .padding(.trailing, GoalsDesignTokens.rowHorizontalPadding)
        .frame(height: GoalsDesignTokens.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sidebarRowChrome(isSelected: isSelected, isHovered: rowHover)
        .onTapGesture { onRowTap() }
        .onHover { rowHover = $0 }
        .accessibilityIdentifier("VerticalTabsSidebar.Goals.outlineRow")
    }
}

struct GoalCadenceRow: View {
    let displayName: String
    let due: GoalDueDescriptor
    let isCompleted: Bool
    let isSelected: Bool
    let onTap: () -> Void

    @State private var rowHover = false

    var body: some View {
        HStack(spacing: 8) {
            goalRowTitle(displayName, isCompleted: isCompleted)
            Spacer(minLength: 0)
            goalDuePill(due)
        }
        .padding(.horizontal, GoalsDesignTokens.rowHorizontalPadding)
        .frame(height: GoalsDesignTokens.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sidebarRowChrome(isSelected: isSelected, isHovered: rowHover)
        .onTapGesture { onTap() }
        .onHover { rowHover = $0 }
        .accessibilityIdentifier("VerticalTabsSidebar.Goals.cadenceRow")
    }
}

struct GoalStatusRow: View {
    let status: BrainGoalStatus?
    let unrecognizedStatusRaw: String?
    let displayName: String
    let milestoneDone: Int
    let milestoneTotal: Int
    let isCompleted: Bool
    let isSelected: Bool
    let onTap: () -> Void
    let onChangeStatus: (BrainGoalStatus) -> Void

    @State private var rowHover = false
    @State private var statusHover = false
    @State private var showStatusPicker = false

    var body: some View {
        HStack(spacing: 8) {
            statusButton
            goalRowTitle(displayName, isCompleted: isCompleted)
            Spacer(minLength: 0)
            Text("\(milestoneDone)/\(milestoneTotal)")
                .font(.system(size: GoalsDesignTokens.metaFontSize, weight: .regular))
                .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                .monospacedDigit()
        }
        .padding(.horizontal, GoalsDesignTokens.rowHorizontalPadding)
        .frame(height: GoalsDesignTokens.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sidebarRowChrome(isSelected: isSelected, isHovered: rowHover)
        .onTapGesture { onTap() }
        .onHover { rowHover = $0 }
        .accessibilityIdentifier("VerticalTabsSidebar.Goals.statusRow")
    }

    @ViewBuilder
    private var statusButton: some View {
        // Task 와 동일 3분기 패턴 (status / unrecognized / nil).
        Button(action: { showStatusPicker = true }) {
            Group {
                if let status {
                    StatusGlyph(shape: status.glyphShape)
                } else if unrecognizedStatusRaw != nil {
                    unknownGlyph
                } else {
                    Circle()
                        .strokeBorder(BVColor.fgFaint, style: StrokeStyle(lineWidth: 1, dash: [2, 1.4]))
                }
            }
            .statusGlyphHitBox(hover: statusHover)
        }
        .buttonStyle(.plain)
        .onHover { statusHover = $0 }
        .panelPopover(isPresented: $showStatusPicker, alignment: .leading) {
            OptionPicker(
                current: status,
                ordered: BrainGoalStatus.allCases,
                title: String(localized: "task.picker.status.title", defaultValue: "Change status"),
                label: { $0.localizedLabel },
                glyph: { StatusGlyph(shape: $0.glyphShape) },
                onSelect: { selected in
                    if let selected { onChangeStatus(selected) }
                    showStatusPicker = false
                }
            )
        }
    }

    private var unknownGlyph: some View {
        ZStack {
            Circle().fill(BVColor.fgFaint.opacity(0.3))
            Text("?")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(BVColor.fgMute)
        }
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
