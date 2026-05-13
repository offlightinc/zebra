import SwiftUI

// MARK: - Router

/// Routes the parse result to the right inspector. Mirrors the
/// `InspectorBody` function in the prototype's `panel.jsx`.
struct BrainObjectInspectorView: View {
    let parse: BrainObjectParse?
    /// Best-effort link routing. v0.1 stubs this — the design contract says
    /// rows stay clickable even when the target cannot be resolved.
    var onActivateRelation: ((BrainObjectRef) -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(BVColor.bgElev.ignoresSafeArea())
    }

    @ViewBuilder
    private var content: some View {
        switch parse?.result {
        case .none:
            LoadingInspectorView()
        case .some(.success(let object)):
            switch object {
            case .task(let t): TaskInspectorView(task: t, onActivateRelation: onActivateRelation)
            case .goal(let g): GoalInspectorView(goal: g, onActivateRelation: onActivateRelation)
            case .note(let n): DocInspectorView(note: n, onActivateRelation: onActivateRelation)
            case .unknown(let u): UnknownInspectorView(unknown: u)
            }
        case .some(.failure(let err)):
            FallbackInspectorView(error: err)
        }
    }
}

// MARK: - Task

struct TaskInspectorView: View {
    let task: TaskObject
    var onActivateRelation: ((BrainObjectRef) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InspectorHeader(tag: .task, title: task.title)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // identity → state → progress → impediments → relations → meta
                    InspectorSection {
                        PropertyRow(label: String(localized: "brain.row.status", defaultValue: "Status"), icon: "circle.dotted") {
                            StatusPillView(status: task.status)
                        }
                        PropertyRow(label: String(localized: "brain.row.priority", defaultValue: "Priority"), icon: "flag") {
                            PriorityPillView(priority: task.priority)
                        }
                        PropertyRow(label: String(localized: "brain.row.owner", defaultValue: "Owner"), icon: "person") {
                            PersonChipView(handle: task.owner)
                        }
                        PropertyRow(label: String(localized: "brain.row.reviewer", defaultValue: "Reviewer"), icon: "person.crop.circle") {
                            PersonChipView(handle: task.reviewer)
                        }
                        PropertyRow(label: String(localized: "brain.row.due", defaultValue: "Due"), icon: "calendar") {
                            DateBadgeView(date: task.due, kind: .due)
                        }
                        PropertyRow(label: String(localized: "brain.row.tags", defaultValue: "Tags"), icon: "number", layout: .stack) {
                            TagFlow(tags: task.tags)
                        }
                    }

                    if let cl = task.checklist {
                        InspectorSection(title: String(localized: "brain.section.progress", defaultValue: "Progress")) {
                            VStack(alignment: .leading, spacing: 6) {
                                ProgressBarView(fraction: Double(cl.done) / Double(max(1, cl.total)), trailing: "\(cl.done)/\(cl.total)")
                                Text("\(cl.total - cl.done) open · \(cl.done) done")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(BVColor.fgFaint)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                        }
                    }

                    if !task.blockedBy.isEmpty {
                        InspectorSection(
                            title: String(localized: "brain.section.blockedBy", defaultValue: "Blocked by"),
                            count: task.blockedBy.count
                        ) {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(task.blockedBy, id: \.self) { r in
                                    RelationRowView(ref: r, onActivate: onActivateRelation)
                                }
                                if let reason = task.blockedReason {
                                    HStack(alignment: .top, spacing: 6) {
                                        Image(systemName: "minus.circle")
                                            .foregroundColor(BVColor.priorityUrgent)
                                            .font(.system(size: 11))
                                        Text(reason)
                                            .font(.system(size: 11).italic())
                                            .foregroundColor(BVColor.fgMute)
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 6)
                                }
                            }
                        }
                    }

                    if !task.related.isEmpty {
                        InspectorSection(
                            title: String(localized: "brain.section.related", defaultValue: "Related"),
                            count: task.related.count
                        ) {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(task.related, id: \.self) { r in
                                    RelationRowView(ref: r, onActivate: onActivateRelation)
                                }
                            }
                        }
                    }

                    InspectorSection(title: String(localized: "brain.section.meta", defaultValue: "Meta")) {
                        PropertyRow(label: String(localized: "brain.row.updated", defaultValue: "Updated"), icon: "calendar") {
                            DateBadgeView(date: task.lastUpdated, kind: .meta)
                        }
                        if let n = task.backlinks {
                            PropertyRow(label: String(localized: "brain.row.backlinks", defaultValue: "Backlinks"), icon: "link") {
                                Text(String(localized: "brain.row.backlinksValue", defaultValue: "\(n) references"))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(BVColor.fgMute)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Goal

struct GoalInspectorView: View {
    let goal: GoalObject
    var onActivateRelation: ((BrainObjectRef) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InspectorHeader(tag: .goal, title: goal.title, secondary: goal.goalId)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    InspectorSection {
                        PropertyRow(label: String(localized: "brain.row.status", defaultValue: "Status"), icon: "circle.dotted") {
                            StatusPillView(status: goal.status)
                        }
                        PropertyRow(label: String(localized: "brain.row.owner", defaultValue: "Owner"), icon: "person") {
                            PersonChipView(handle: goal.owner)
                        }
                        PropertyRow(label: String(localized: "brain.row.target", defaultValue: "Target"), icon: "calendar") {
                            DateBadgeView(date: goal.targetDate, kind: .due)
                        }
                        PropertyRow(label: String(localized: "brain.row.cadence", defaultValue: "Cadence"), icon: "clock") {
                            if let c = goal.reviewCadence {
                                Text(c.capitalized)
                                    .font(.system(size: 12))
                                    .foregroundColor(BVColor.fg)
                            } else {
                                EmptyValue()
                            }
                        }
                        if let parent = goal.parentGoal {
                            PropertyRow(label: String(localized: "brain.row.parent", defaultValue: "Parent"), icon: "arrow.triangle.branch", layout: .stack) {
                                RelationRowView(ref: parent, onActivate: onActivateRelation)
                                    .padding(.horizontal, -16) // RelationRowView adds its own gutter
                            }
                        }
                    }

                    if let frac = goal.progressFraction {
                        InspectorSection(title: String(localized: "brain.section.progress", defaultValue: "Progress")) {
                            VStack(alignment: .leading, spacing: 6) {
                                ProgressBarView(fraction: frac, trailing: "\(Int(frac * 100))%")
                                if let done = goal.tasksDone, let open = goal.tasksOpen {
                                    Text("\(done) of \(done + open) tasks done")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(BVColor.fgFaint)
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 4)
                        }
                    }

                    if !goal.metrics.isEmpty {
                        InspectorSection(
                            title: String(localized: "brain.section.metrics", defaultValue: "Metrics"),
                            count: goal.metrics.count
                        ) {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(goal.metrics.enumerated()), id: \.offset) { _, m in
                                    MetricRowView(metric: m)
                                }
                            }
                        }
                    }

                    if !goal.milestones.isEmpty {
                        InspectorSection(
                            title: String(localized: "brain.section.milestones", defaultValue: "Milestones"),
                            count: goal.milestones.count
                        ) {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(goal.milestones.enumerated()), id: \.offset) { _, m in
                                    MilestoneRowView(milestone: m)
                                }
                            }
                        }
                    }

                    if !goal.subgoals.isEmpty {
                        InspectorSection(
                            title: String(localized: "brain.section.subgoals", defaultValue: "Subgoals"),
                            count: goal.subgoals.count
                        ) {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(goal.subgoals, id: \.self) { r in
                                    RelationRowView(ref: r, onActivate: onActivateRelation)
                                }
                            }
                        }
                    }

                    if !goal.tasks.isEmpty {
                        InspectorSection(
                            title: String(localized: "brain.section.tasks", defaultValue: "Tasks"),
                            count: goal.tasks.count
                        ) {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(goal.tasks, id: \.self) { r in
                                    RelationRowView(ref: r, onActivate: onActivateRelation)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Document (generic note)

struct DocInspectorView: View {
    let note: NoteObject
    var onActivateRelation: ((BrainObjectRef) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !note.frontmatter.isEmpty {
                        InspectorSection {
                            ForEach(note.frontmatter, id: \.key) { field in
                                PropertyRow(label: field.key, icon: icon(for: field.key)) {
                                    FrontmatterValueView(value: field.value)
                                }
                            }
                        }
                    }

                    if !note.headings.isEmpty {
                        InspectorSection(
                            title: String(localized: "brain.section.onThisPage", defaultValue: "On this page"),
                            count: note.headings.count
                        ) {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(note.headings.enumerated()), id: \.offset) { idx, h in
                                    HStack(spacing: 7) {
                                        Image(systemName: "number")
                                            .font(.system(size: 10))
                                            .foregroundColor(BVColor.fgFaint)
                                        Text(h)
                                            .font(.system(size: 12))
                                            .foregroundColor(BVColor.fg)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                        Spacer(minLength: 6)
                                        Text("§\(idx + 1)")
                                            .font(.system(size: 10.5, design: .monospaced))
                                            .foregroundColor(BVColor.fgFaint)
                                    }
                                    .padding(.horizontal, 16)
                                    .frame(minHeight: 24)
                                }
                            }
                        }
                    }

                    if !note.seeAlso.isEmpty {
                        InspectorSection(
                            title: String(localized: "brain.section.seeAlso", defaultValue: "See also"),
                            count: note.seeAlso.count
                        ) {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(note.seeAlso, id: \.self) { r in
                                    RelationRowView(ref: r, onActivate: onActivateRelation)
                                }
                            }
                        }
                    }

                    InspectorSection(title: String(localized: "brain.section.meta", defaultValue: "Meta")) {
                        if let n = note.backlinks {
                            VStack(alignment: .leading, spacing: 0) {
                                PropertyRow(label: String(localized: "brain.row.backlinks", defaultValue: "Backlinks"), icon: "link") {
                                    Text(String(localized: "brain.row.backlinksValue", defaultValue: "\(n) references"))
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(BVColor.fgMute)
                                }
                                if !note.referencedIn.isEmpty {
                                    VStack(alignment: .leading, spacing: 0) {
                                        ForEach(note.referencedIn, id: \.self) { r in
                                            RelationRowView(ref: r, onActivate: onActivateRelation)
                                        }
                                    }
                                    .padding(.top, 2)
                                }
                            }
                        } else {
                            PropertyRow(label: String(localized: "brain.row.backlinks", defaultValue: "Backlinks"), icon: "link") {
                                EmptyValue()
                            }
                        }
                    }

                }
            }
        }
    }

    private func icon(for key: String) -> String {
        switch key {
        case "aliases": return "link"
        case "tags": return "number"
        case "created", "updated", "date": return "calendar"
        default: return "doc.text"
        }
    }
}

private struct FrontmatterValueView: View {
    let value: BrainFrontmatterValue

    var body: some View {
        switch value {
        case .null:
            EmptyValue()
        case .scalar(let value):
            Text(value)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundColor(BVColor.fg)
                .lineLimit(3)
                .truncationMode(.tail)
                .textSelection(.enabled)
        case .array(let values):
            let items = values.map(Self.flatString)
            if items.isEmpty {
                EmptyValue()
            } else {
                BrainInspectorFlowLayout(spacing: 4) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        FrontmatterChip(text: item)
                    }
                }
            }
        case .map:
            Text(Self.flatString(value))
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundColor(BVColor.fg)
                .lineLimit(3)
                .truncationMode(.tail)
                .textSelection(.enabled)
        }
    }

    private static func flatString(_ value: BrainFrontmatterValue) -> String {
        switch value {
        case .null:
            return "—"
        case .scalar(let string):
            return string
        case .array(let values):
            return "[" + values.map(flatString).joined(separator: ", ") + "]"
        case .map(let pairs):
            return "{" + pairs.map { "\($0.key): \(flatString($0.value))" }.joined(separator: ", ") + "}"
        }
    }
}

private struct FrontmatterChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundColor(BVColor.fgMute)
            .padding(.horizontal, 5)
            .frame(height: 18)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(BVColor.bgInput)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(BVColor.border))
            )
    }
}

// MARK: - Unknown (no/unrecognized type, but parse succeeded)

/// Catch-all that surfaces every parsed frontmatter key verbatim under a
/// "Frontmatter" section so nothing is silently dropped. This is the
/// design's explicit guarantee for files with unknown `type:` values.
struct UnknownInspectorView: View {
    let unknown: UnknownObject

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InspectorHeader(tag: .document, title: unknown.title)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if unknown.frontmatter.isEmpty {
                        InspectorSection {
                            HStack {
                                Text(String(localized: "brain.unknown.noFrontmatter", defaultValue: "No frontmatter detected"))
                                    .font(.system(size: 12).italic())
                                    .foregroundColor(BVColor.fgFaint)
                                Spacer()
                            }
                            .padding(.horizontal, 16).padding(.vertical, 4)
                        }
                    } else {
                        InspectorSection(
                            title: String(localized: "brain.section.frontmatter", defaultValue: "Frontmatter"),
                            count: unknown.frontmatter.count
                        ) {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(unknown.frontmatter.enumerated()), id: \.offset) { _, kv in
                                    PropertyRow(label: kv.key, icon: "doc.text") {
                                        Text(kv.value)
                                            .font(.system(size: 11.5, design: .monospaced))
                                            .foregroundColor(BVColor.fg)
                                            .lineLimit(2)
                                            .truncationMode(.tail)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Fallback (parse error)

struct FallbackInspectorView: View {
    let error: BrainObjectParseError

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InspectorHeader(
                tag: .error,
                title: String(localized: "brain.fallback.title", defaultValue: "No structured view"),
                secondary: String(localized: "brain.fallback.subtitle", defaultValue: "Markdown still renders on the left")
            )

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(BVColor.priorityUrgent)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "brain.fallback.bannerTitle", defaultValue: "Frontmatter parse error"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(nsColor: NSColor(srgbRed: 1.0, green: 0.86, blue: 0.86, alpha: 1)))
                    Text(String(localized: "brain.fallback.location", defaultValue: "line \(error.line), col \(error.column)"))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(Color(nsColor: NSColor(srgbRed: 1.0, green: 0.78, blue: 0.78, alpha: 1)).opacity(0.75))
                    Text(error.message)
                        .font(.system(size: 11))
                        .foregroundColor(Color(nsColor: NSColor(srgbRed: 1.0, green: 0.86, blue: 0.86, alpha: 1)))
                        .padding(.top, 4)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(BVColor.priorityUrgent.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(BVColor.priorityUrgent.opacity(0.25)))
            )
            .padding(.horizontal, 16)
            .padding(.top, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    InspectorSection(title: String(localized: "brain.fallback.detected", defaultValue: "Detected")) {
                        PropertyRow(label: String(localized: "brain.row.type", defaultValue: "Type"), icon: "doc.text") {
                            Text(String(localized: "brain.fallback.unknown", defaultValue: "unknown"))
                                .font(.system(size: 12).italic())
                                .foregroundColor(BVColor.fgFaint)
                        }
                        PropertyRow(label: String(localized: "brain.row.title", defaultValue: "Title"), icon: "doc.text") {
                            EmptyValue()
                        }
                    }

                    VStack(spacing: 6) {
                        recoveryButton(String(localized: "brain.fallback.openRaw", defaultValue: "Open raw .md"))
                        recoveryButton(String(localized: "brain.fallback.copyError", defaultValue: "Copy parse error"))
                        recoveryButton(String(localized: "brain.fallback.report", defaultValue: "Report bad file"))
                    }
                    .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 16)
                }
            }
        }
    }

    private func recoveryButton(_ label: String) -> some View {
        // v0.1: stubs — the design doc lists these as the recovery action set
        // but the wiring (open raw, copy error, report) is post-MVP.
        Button(action: {}) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundColor(BVColor.fg)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(BVColor.borderStrong)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Loading

struct LoadingInspectorView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                SkeletonBar(width: 56, height: 9)
                SkeletonBar(width: 220, height: 14)
                SkeletonBar(width: 140, height: 14)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14).padding(.bottom, 12)
            .overlay(alignment: .bottom) { Rectangle().fill(BVColor.border).frame(height: 1) }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(0..<5, id: \.self) { i in
                    HStack(spacing: 10) {
                        SkeletonBar(width: 56, height: 9).frame(width: 88, alignment: .leading)
                        SkeletonBar(width: 60 + CGFloat((i * 12) % 70), height: 10)
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 4).frame(minHeight: 26)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(String(localized: "brain.loading.label", defaultValue: "Loading object inspector")))
    }
}

/// Shimmer-able placeholder. Disables animation under reduce-motion per
/// the design's a11y contract.
struct SkeletonBar: View {
    let width: CGFloat
    let height: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1.0

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(BVColor.bgInput)
            .frame(width: width, height: height)
            .overlay(
                GeometryReader { geo in
                    let w = geo.size.width
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.04),
                            Color.white.opacity(0.08),
                            Color.white.opacity(0.04),
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: w * 1.6)
                    .offset(x: phase * w)
                }
                .mask(RoundedRectangle(cornerRadius: 4))
            )
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1.6
                }
            }
    }
}

// MARK: - Empty

struct EmptyInspectorView: View {
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 36, height: 36)
                Image(systemName: "doc.text")
                    .font(.system(size: 16))
                    .foregroundColor(BVColor.fgFaint)
            }
            Text(String(localized: "brain.empty.title", defaultValue: "No object selected"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(BVColor.fg)
            Text(String(localized: "brain.empty.message", defaultValue: "Open a .md file from the vault to see its structured object here."))
                .font(.system(size: 11.5))
                .foregroundColor(BVColor.fgMute)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
