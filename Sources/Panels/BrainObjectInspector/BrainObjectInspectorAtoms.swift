import SwiftUI

// MARK: - Token palette (dark)

/// The design committed to a dark token palette only. The token names
/// mirror the CSS custom properties used in the prototype so a reviewer
/// can cross-reference. Light-mode appearance follows the same alpha
/// scale against the system background and reads correctly without a
/// separate ramp.
enum BVColor {
    static let bg = Color(nsColor: NSColor(srgbRed: 0x1f / 255.0, green: 0x1f / 255.0, blue: 0x1f / 255.0, alpha: 1.0))
    static let bgElev = Color(nsColor: NSColor(srgbRed: 0x26 / 255.0, green: 0x26 / 255.0, blue: 0x26 / 255.0, alpha: 1.0))
    static let bgInput = Color.white.opacity(0.035)
    static let bgHover = Color.white.opacity(0.05)
    static let fg = Color.white.opacity(0.92)
    static let fgMute = Color.white.opacity(0.58)
    static let fgFaint = Color.white.opacity(0.38)
    static let fgGhost = Color.white.opacity(0.22)
    static let border = Color.white.opacity(0.07)
    static let borderStrong = Color.white.opacity(0.12)
    static let accent = Color(nsColor: NSColor(srgbRed: 0, green: 145 / 255.0, blue: 1.0, alpha: 1.0))

    // Status hues match the Linear-inspired palette in notes.jsx §3.
    // HTML 디자인 (zebra/project/Zebra - Linear style.html) 기준 팔레트.
    // backlog/todo: 회색 stroke (dash vs solid 글리프 차이)
    // inprogress(doing): amber #f59e0b
    // blocked: red #ef4444
    // done(completed): blue #2563eb
    static let statusTodo = Color(nsColor: NSColor(srgbRed: 0x9c / 255.0, green: 0xa3 / 255.0, blue: 0xaf / 255.0, alpha: 1.0))
    static let statusDoing = Color(nsColor: NSColor(srgbRed: 0xf5 / 255.0, green: 0x9e / 255.0, blue: 0x0b / 255.0, alpha: 1.0))
    static let statusBlocked = Color(nsColor: NSColor(srgbRed: 0xef / 255.0, green: 0x44 / 255.0, blue: 0x44 / 255.0, alpha: 1.0))
    static let statusWaiting = Color(nsColor: NSColor(srgbRed: 0xe0 / 255.0, green: 0xb3 / 255.0, blue: 0x41 / 255.0, alpha: 1.0))
    static let statusCompleted = Color(nsColor: NSColor(srgbRed: 0x25 / 255.0, green: 0x63 / 255.0, blue: 0xeb / 255.0, alpha: 1.0))
    static let statusCanceled = Color(nsColor: NSColor(srgbRed: 0x6e / 255.0, green: 0x6e / 255.0, blue: 0x6e / 255.0, alpha: 1.0))

    static let priorityUrgent = statusBlocked
    static let priorityHigh = Color(nsColor: NSColor(srgbRed: 0xf0 / 255.0, green: 0x8a / 255.0, blue: 0x3e / 255.0, alpha: 1.0))
    static let priorityNormal = Color(nsColor: NSColor(srgbRed: 0x6c / 255.0, green: 0xae / 255.0, blue: 0xdb / 255.0, alpha: 1.0))
    static let priorityLow = Color(nsColor: NSColor(srgbRed: 0x77 / 255.0, green: 0x77 / 255.0, blue: 0x77 / 255.0, alpha: 1.0))
}

// MARK: - Type tag

/// Small-caps eyebrow at the top of every inspector. Encodes which sub-
/// view rendered the panel, not the file kind — the prototype calls
/// `note` "Document" in the tag.
struct TypeTagView: View {
    enum Kind { case task, goal, note, document, error }
    let kind: Kind

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .opacity(0.7)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.9)
                .textCase(.uppercase)
        }
        .foregroundColor(kind == .error ? BVColor.priorityUrgent : BVColor.fgMute)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch kind {
        case .task: return "checkmark.square"
        case .goal: return "scope"
        case .note, .document: return "doc.text"
        case .error: return "exclamationmark.triangle"
        }
    }
    private var label: String {
        switch kind {
        case .task: return String(localized: "brain.tag.task", defaultValue: "Task")
        case .goal: return String(localized: "brain.tag.goal", defaultValue: "Goal")
        case .note, .document: return String(localized: "brain.tag.document", defaultValue: "Document")
        case .error: return String(localized: "brain.tag.error", defaultValue: "Couldn't parse object")
        }
    }
}

// MARK: - Inspector header

/// Top block of each inspector: type tag, title, optional monospaced
/// secondary ID (goal_id, parse-error subtitle, etc.).
struct InspectorHeader: View {
    let tag: TypeTagView.Kind
    let title: String
    var secondary: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TypeTagView(kind: tag)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(BVColor.fg)
                .tracking(-0.07)
                .lineSpacing(2)
                .textSelection(.enabled)
                .padding(.bottom, secondary == nil ? 0 : 4)
            if let secondary {
                Text(secondary)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(BVColor.fgFaint)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(BVColor.border).frame(height: 1)
        }
    }
}

// MARK: - Section

/// Grouped block with uppercase eyebrow + optional monospaced count pill.
/// The eyebrow uses the same 10pt/600 tracking as the type tag for
/// vertical rhythm.
struct InspectorSection<Content: View>: View {
    let title: String?
    let count: Int?
    @ViewBuilder var content: () -> Content

    init(title: String? = nil, count: Int? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.count = count
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                HStack {
                    Text(title)
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundColor(BVColor.fgFaint)
                    Spacer()
                    if let count {
                        Text("\(count)")
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundColor(BVColor.fgMute)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(BVColor.bgInput)
                                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(BVColor.border))
                            )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6).padding(.bottom, 8)
            }
            content()
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(BVColor.border).frame(height: 1)
        }
    }
}

// MARK: - Property row

/// 88pt label · value grid. Values may wrap; labels never do.
/// Stack variant (used for tag/alias chips) lifts the label to its own
/// line so the chips can flow.
struct PropertyRow<Value: View>: View {
    enum Layout { case inline, stack }

    let label: String
    let icon: String
    let layout: Layout
    @ViewBuilder var value: () -> Value

    init(label: String, icon: String, layout: Layout = .inline, @ViewBuilder value: @escaping () -> Value) {
        self.label = label
        self.icon = icon
        self.layout = layout
        self.value = value
    }

    var body: some View {
        switch layout {
        case .inline:
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                labelView.frame(width: 88, alignment: .leading)
                value()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .frame(minHeight: 26)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(label))
        case .stack:
            VStack(alignment: .leading, spacing: 6) {
                labelView
                value().frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
        }
    }

    private var labelView: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(BVColor.fgMute.opacity(0.7))
            Text(label)
                .font(.system(size: 11.5))
                .foregroundColor(BVColor.fgMute)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}

/// Placeholder for absent values. The design is explicit: never hide
/// the row — present an italic em-dash instead.
struct EmptyValue: View {
    var body: some View {
        Text("—")
            .font(.system(size: 12).italic())
            .foregroundColor(BVColor.fgFaint)
    }
}

// MARK: - Status glyph

/// Linear-style status disc. Each state gets a distinct silhouette so
/// status is legible at 12pt even without color.
struct StatusGlyph: View {
    let status: BrainTaskStatus

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height)
            let r = s / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let circleRect = CGRect(x: center.x - r + 1, y: center.y - r + 1, width: s - 2, height: s - 2)
            let color = nsColor(for: status)

            switch status {
            case .backlog:
                // HTML: stroke gray dasharray 2 2 — "아직 시작 전" 의미.
                ctx.stroke(Path(ellipseIn: circleRect), with: .color(color),
                           style: StrokeStyle(lineWidth: 1.2, dash: [2, 2]))
            case .todo:
                // HTML: solid gray stroke 원. 점선이 아니다.
                ctx.stroke(Path(ellipseIn: circleRect), with: .color(color), lineWidth: 1.2)
            case .inprogress:
                ctx.stroke(Path(ellipseIn: circleRect), with: .color(color), lineWidth: 1.2)
                var fill = Path()
                fill.move(to: center)
                fill.addArc(center: center, radius: r - 1, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
                fill.closeSubpath()
                ctx.fill(fill, with: .color(color))
            case .blocked:
                ctx.stroke(Path(ellipseIn: circleRect), with: .color(color), lineWidth: 1.2)
                var line = Path()
                let inset: CGFloat = 3
                line.move(to: CGPoint(x: circleRect.minX + inset, y: center.y))
                line.addLine(to: CGPoint(x: circleRect.maxX - inset, y: center.y))
                ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            case .waiting:
                ctx.fill(Path(ellipseIn: circleRect), with: .color(color))
                for dx in [-2.4, 0.0, 2.4] {
                    let dot = CGRect(x: center.x + CGFloat(dx) - 0.8, y: center.y - 0.8, width: 1.6, height: 1.6)
                    ctx.fill(Path(ellipseIn: dot), with: .color(Color(nsColor: .black).opacity(0.85)))
                }
            case .done:
                // HTML: fill blue + 흰색 체크. 어두운 체크 X.
                ctx.fill(Path(ellipseIn: circleRect), with: .color(color))
                var check = Path()
                check.move(to: CGPoint(x: center.x - 2.4, y: center.y + 0.0))
                check.addLine(to: CGPoint(x: center.x - 0.8, y: center.y + 1.6))
                check.addLine(to: CGPoint(x: center.x + 2.4, y: center.y - 1.6))
                ctx.stroke(check, with: .color(.white),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            case .canceled:
                ctx.fill(Path(ellipseIn: circleRect), with: .color(color))
                var line = Path()
                line.move(to: CGPoint(x: center.x - 2.5, y: center.y))
                line.addLine(to: CGPoint(x: center.x + 2.5, y: center.y))
                ctx.stroke(line, with: .color(Color(nsColor: .black).opacity(0.85)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            }
        }
    }

    private func nsColor(for status: BrainTaskStatus) -> Color {
        switch status {
        case .backlog: return BVColor.statusTodo
        case .todo: return BVColor.statusTodo
        case .inprogress: return BVColor.statusDoing
        case .blocked: return BVColor.statusBlocked
        case .waiting: return BVColor.statusWaiting
        case .done: return BVColor.statusCompleted
        case .canceled: return BVColor.statusCanceled
        }
    }
}

// MARK: - Priority bars

/// Three vertical bars, low → high, lit up to `level`. Mirrors the
/// `.bv-priority-icon` CSS in the prototype.
struct PriorityBars: View {
    let level: Int
    let color: Color
    var body: some View {
        HStack(alignment: .bottom, spacing: 1) {
            bar(height: 3, lit: level >= 1)
            bar(height: 6, lit: level >= 2)
            bar(height: 9, lit: level >= 3)
        }
        .frame(height: 11)
    }
    private func bar(height: CGFloat, lit: Bool) -> some View {
        RoundedRectangle(cornerRadius: 0.5)
            .fill(color)
            .opacity(lit ? 1 : 0.3)
            .frame(width: 2.5, height: height)
    }
}

// MARK: - Person color

/// Single source of truth for per-handle avatar color. Centralizes the
/// known-handle palette and hash-derived fallback used by
/// `EditableOwnerChip` and `OwnerPickerView`.
enum BrainPersonColor {
    private static let known: [String: Color] = [
        "dan": Color(nsColor: NSColor(srgbRed: 0x5b / 255, green: 0x9d / 255, blue: 0xf9 / 255, alpha: 1)),
        "leo": Color(nsColor: NSColor(srgbRed: 0xc1 / 255, green: 0x84 / 255, blue: 0xe0 / 255, alpha: 1)),
        "alex": Color(nsColor: NSColor(srgbRed: 0x54 / 255, green: 0xc0 / 255, blue: 0x71 / 255, alpha: 1)),
        "sam": Color(nsColor: NSColor(srgbRed: 0xe0 / 255, green: 0xb3 / 255, blue: 0x41 / 255, alpha: 1)),
        "pat": Color(nsColor: NSColor(srgbRed: 0xf0 / 255, green: 0x8a / 255, blue: 0x3e / 255, alpha: 1)),
        "mira": Color(nsColor: NSColor(srgbRed: 0xef / 255, green: 0x5a / 255, blue: 0x5a / 255, alpha: 1)),
    ]

    static func color(for handle: String) -> Color {
        if let c = known[handle] { return c }
        var hasher = Hasher(); hasher.combine(handle)
        let h = abs(hasher.finalize())
        let hue = Double(h % 360) / 360.0
        return Color(hue: hue, saturation: 0.55, brightness: 0.78)
    }
}

// MARK: - Date badge

struct DateBadgeView: View {
    let date: BrainDate?
    /// `.due` evaluates overdue/soon; `.meta` only renders the absolute date.
    enum Kind { case due, meta }
    let kind: Kind

    var body: some View {
        guard let date else {
            return AnyView(EmptyValue())
        }
        let days = Calendar(identifier: .gregorian).dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: date.date)).day ?? 0
        let overdue = kind == .due && days < 0
        let soon = kind == .due && days >= 0 && days <= 3
        let color: Color = overdue ? BVColor.priorityUrgent : (soon ? BVColor.priorityHigh : BVColor.fg)
        return AnyView(
            HStack(spacing: 5) {
                Image(systemName: "calendar")
                    .font(.system(size: 10))
                    .foregroundColor(color.opacity(0.7))
                Text(absoluteString(date.date))
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundColor(color)
                if let rel = relativeString(days: days, kind: kind) {
                    Text("· \(rel)")
                        .font(.system(size: 10.5).monospacedDigit())
                        .foregroundColor(BVColor.fgFaint)
                }
            }
        )
    }

    private func absoluteString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: d)
    }
    private func relativeString(days: Int, kind: Kind) -> String? {
        // Meta dates skip the relative caption — the absolute date already
        // gives the reader enough resolution to scan.
        if kind == .meta { return nil }
        if days < -14 { return nil }
        if days < 0 { return String(localized: "brain.date.daysAgo", defaultValue: "\(abs(days))d ago") }
        if days == 0 { return String(localized: "brain.date.today", defaultValue: "today") }
        if days == 1 { return String(localized: "brain.date.tomorrow", defaultValue: "tomorrow") }
        if days <= 14 { return String(localized: "brain.date.inDays", defaultValue: "in \(days)d") }
        return nil
    }
}

// MARK: - Tags

struct TagChipView: View {
    let tag: String
    var body: some View {
        HStack(spacing: 2) {
            Text("#").foregroundColor(BVColor.fgGhost)
            Text(tag)
        }
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

struct TagFlow: View {
    let tags: [String]
    /// When true, render as a single horizontal row (chips that overflow the
    /// available width are clipped). When false (default), wrap onto multiple
    /// rows via `BrainInspectorFlowLayout`. Inline rows in property tables
    /// generally want `true`; standalone tag clouds want `false`.
    var singleLine: Bool = false

    var body: some View {
        if tags.isEmpty {
            EmptyValue()
        } else if singleLine {
            HStack(spacing: 4) {
                ForEach(tags, id: \.self) { TagChipView(tag: $0) }
            }
            .lineLimit(1)
            .clipped()
        } else {
            BrainInspectorFlowLayout(spacing: 4) {
                ForEach(tags, id: \.self) { TagChipView(tag: $0) }
            }
        }
    }
}

/// Wrapping container for tags and aliases. Renamed from the generic
/// `FlowLayout` because the existing Feed panel ships its own
/// `FlowLayout` and the names collide.
struct BrainInspectorFlowLayout: Layout {
    var spacing: CGFloat = 4
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, w: CGFloat = 0
        for sv in subviews {
            let sz = sv.sizeThatFits(.unspecified)
            if x + sz.width > maxW {
                w = max(w, x - spacing)
                x = 0
                y += rowH + spacing
                rowH = 0
            }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
        w = max(w, x - spacing)
        return CGSize(width: w, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxW = bounds.width
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, rowH: CGFloat = 0
        for sv in subviews {
            let sz = sv.sizeThatFits(.unspecified)
            if x - bounds.minX + sz.width > maxW {
                x = bounds.minX
                y += rowH + spacing
                rowH = 0
            }
            sv.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}

// MARK: - Relation row

/// Linked-object row. The leading icon is the resolved type if we have a
/// hint, otherwise just the type tag's icon. Click-through is best-effort
/// for v0.1 — the row stays clickable but the action is a stub until the
/// vault resolver lands.
struct RelationRowView: View {
    let ref: BrainObjectRef
    var statusOverride: BrainTaskStatus? = nil
    var showsLeadingIcon: Bool = true
    var showsTrailingMeta: Bool = true
    var onActivate: ((BrainObjectRef) -> Void)? = nil
    @State private var isHovering = false

    var body: some View {
        Button(action: { onActivate?(ref) }) {
            HStack(spacing: 7) {
                if showsLeadingIcon {
                    Group {
                        if let s = statusOverride {
                            StatusGlyph(status: s).frame(width: 12, height: 12)
                        } else {
                            Image(systemName: inferredSymbol)
                                .font(.system(size: 11))
                                .foregroundColor(BVColor.fgMute)
                                .opacity(0.7)
                        }
                    }
                }
                Text(ref.displayTitle)
                    .font(.system(size: 12))
                    .foregroundColor(BVColor.fg)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 6)
                if showsTrailingMeta, let meta = compactMeta {
                    Text(meta)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(BVColor.fgFaint)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            guard hovering != isHovering else { return }
            isHovering = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onDisappear {
            if isHovering {
                NSCursor.pop()
                isHovering = false
            }
        }
    }

    private var inferredSymbol: String {
        let r = ref.raw
        if r.hasPrefix("tasks/") { return "checkmark.square" }
        if r.hasPrefix("goals/") || ref.looksLikeId { return "scope" }
        return "doc.text"
    }

    private var compactMeta: String? {
        let meta = ref.displayMeta.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !meta.isEmpty, meta != ref.raw else { return nil }
        guard meta.count <= 24, !meta.contains(" "), !meta.contains("\n") else { return nil }
        return meta
    }
}

// MARK: - Progress

struct ProgressBarView: View {
    /// 0…1
    let fraction: Double
    let trailing: String?

    var body: some View {
        HStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.06))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(BVColor.statusDoing)
                        .frame(width: geo.size.width * CGFloat(max(0, min(1, fraction))))
                }
            }
            .frame(height: 6)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(BVColor.fgMute)
                    .frame(minWidth: 36, alignment: .trailing)
            }
        }
    }
}

// MARK: - Metric

struct MetricRowView: View {
    let metric: BrainMetric
    var body: some View {
        let trendUp = metric.to > metric.from
        let trendColor: Color = trendUp ? BVColor.statusCompleted : BVColor.priorityHigh
        return HStack(spacing: 8) {
            Text(metric.name)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(BVColor.fgMute)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                Text(format(metric.from))
                    .foregroundColor(BVColor.fgFaint)
                Text("→").foregroundColor(BVColor.fgFaint)
                Text(format(metric.to))
                    .foregroundColor(BVColor.fg)
                if let unit = metric.unit, !unit.isEmpty {
                    Text(unit).foregroundColor(BVColor.fgFaint)
                }
                Text(trendUp ? "↑" : "↓")
                    .foregroundColor(trendColor)
            }
            .font(.system(size: 11, design: .monospaced).monospacedDigit())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func format(_ d: Double) -> String {
        if d.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(d))
        }
        return String(d)
    }
}

// MARK: - Milestone

struct MilestoneRowView: View {
    let milestone: BrainMilestone
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                if milestone.current {
                    Circle()
                        .fill(BVColor.statusDoing.opacity(0.18))
                        .frame(width: 14, height: 14)
                }
                Circle()
                    .fill(markerColor)
                    .frame(width: 8, height: 8)
            }
            .frame(width: 14)
            Text(milestone.name)
                .font(.system(size: 11.5))
                .foregroundColor(milestone.done ? BVColor.fgMute : BVColor.fg)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            if let date = milestone.date {
                Text(monthDay(date.date))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(BVColor.fgFaint)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
    }

    private var markerColor: Color {
        if milestone.done { return BVColor.statusCompleted }
        if milestone.current { return BVColor.statusDoing }
        return BVColor.fgGhost
    }
    private func monthDay(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return f.string(from: d)
    }
}

// MARK: - Pill chrome

/// 20pt rounded-rectangle pill chrome shared by inspector inline-editable
/// controls (status / priority / cadence). The caller supplies the inner
/// glyph + label `HStack`; this modifier adds the 7pt horizontal padding,
/// fixed height, `bgInput` background, border, and click hit shape.
struct InspectorPillChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(BVColor.bgInput)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(BVColor.border))
            )
            .contentShape(Rectangle())
    }
}

extension View {
    func inspectorPillChrome() -> some View {
        modifier(InspectorPillChrome())
    }
}

// MARK: - Editable Goal status pill

/// Visual glyph for a `BrainGoalStatus`. Reuses `StatusGlyph`'s `BrainTaskStatus`
/// rendering via a small mapping so the editable Goal pill matches the
/// read-only Task pill style.
private func glyphMapping(_ s: BrainGoalStatus) -> BrainTaskStatus {
    switch s {
    case .active: return .inprogress
    case .blocked: return .blocked
    case .draft: return .todo
    case .completed: return .done
    case .archived: return .canceled
    }
}

private func goalStatusLabel(_ s: BrainGoalStatus) -> String {
    switch s {
    case .active: return String(localized: "brain.goal.status.active", defaultValue: "Active")
    case .blocked: return String(localized: "brain.goal.status.blocked", defaultValue: "Blocked")
    case .draft: return String(localized: "brain.goal.status.draft", defaultValue: "Draft")
    case .completed: return String(localized: "brain.goal.status.completed", defaultValue: "Completed")
    case .archived: return String(localized: "brain.goal.status.archived", defaultValue: "Archived")
    }
}

struct EditableGoalStatusPill: View {
    let value: BrainGoalStatus?
    let onChange: (BrainGoalStatus?) -> Void

    @State private var isPresented = false

    var body: some View {
        Button(action: { isPresented = true }) {
            HStack(spacing: 5) {
                if let value {
                    StatusGlyph(status: glyphMapping(value)).frame(width: 12, height: 12)
                    Text(goalStatusLabel(value))
                        .font(.system(size: 11.5))
                        .foregroundColor(BVColor.fg)
                } else {
                    Circle()
                        .strokeBorder(BVColor.fgFaint, style: StrokeStyle(lineWidth: 1, dash: [2, 1.4]))
                        .frame(width: 12, height: 12)
                    Text(String(localized: "brain.editable.setStatus", defaultValue: "Set status..."))
                        .font(.system(size: 11.5).italic())
                        .foregroundColor(BVColor.fgFaint)
                }
            }
            .inspectorPillChrome()
        }
        .buttonStyle(.plain)
        .panelPopover(isPresented: $isPresented) {
            BrainOptionPicker(
                items: BrainGoalStatus.allCases,
                current: value,
                label: { goalStatusLabel($0) },
                glyph: { status in
                    StatusGlyph(status: glyphMapping(status)).frame(width: 14, height: 14)
                },
                onSelect: { selected in
                    if let selected, selected != value {
                        onChange(selected)
                    }
                    isPresented = false
                }
            )
        }
        .accessibilityLabel(Text(value.map(goalStatusLabel) ?? String(localized: "brain.editable.setStatus", defaultValue: "Set status...")))
    }
}

// MARK: - Editable owner chip

struct EditableOwnerChip: View {
    let rawValue: String?
    let peopleSlugs: [String]
    let onChange: (String?) -> Void

    @State private var isPresented = false

    var body: some View {
        Button(action: { isPresented = true }) {
            if let display = displayHandle(from: rawValue), !display.isEmpty {
                ownerChipView(handle: display)
            } else {
                placeholderView
            }
        }
        .buttonStyle(.plain)
        .panelPopover(isPresented: $isPresented) {
            OwnerPickerView(
                current: rawValue,
                slugs: peopleSlugs,
                onSelect: { newValue in
                    if newValue != rawValue {
                        onChange(newValue)
                    }
                    isPresented = false
                }
            )
        }
    }

    private func ownerChipView(handle: String) -> some View {
        let initial = String(handle.prefix(1)).uppercased()
        let color = colorFor(handle: handle)
        return HStack(spacing: 6) {
            Text(initial)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 16, height: 16)
                .background(Circle().fill(color))
            Text(handle)
                .font(.system(size: 11.5))
                .foregroundColor(BVColor.fg)
        }
        .padding(.leading, 3).padding(.trailing, 7)
        .frame(height: 20)
        .background(
            Capsule().fill(BVColor.bgInput)
                .overlay(Capsule().stroke(BVColor.border))
        )
        .contentShape(Rectangle())
    }

    private var placeholderView: some View {
        HStack(spacing: 5) {
            Image(systemName: "person.circle.dashed")
                .font(.system(size: 11))
                .foregroundColor(BVColor.fgFaint)
            Text(String(localized: "brain.editable.setOwner", defaultValue: "Set owner..."))
                .font(.system(size: 11.5).italic())
                .foregroundColor(BVColor.fgFaint)
        }
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background(
            Capsule().fill(BVColor.bgInput)
                .overlay(Capsule().stroke(BVColor.border))
        )
        .contentShape(Rectangle())
    }

    private func colorFor(handle: String) -> Color {
        BrainPersonColor.color(for: handle)
    }
}

/// Extracts the display slug from a raw owner string. `people/foo` → `foo`,
/// `foo` → `foo`. Returns nil if input is nil/empty.
private func displayHandle(from raw: String?) -> String? {
    guard let raw, !raw.isEmpty else { return nil }
    if raw.hasPrefix("people/") {
        let slug = String(raw.dropFirst("people/".count))
        return slug.isEmpty ? nil : slug
    }
    return raw
}

struct OwnerPickerView: View {
    let current: String?
    let slugs: [String]
    let onSelect: (String?) -> Void

    @State private var query: String = ""
    @FocusState private var searchFocused: Bool

    private var filtered: [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return slugs }
        return slugs.filter { $0.lowercased().contains(q) }
    }

    private var currentSlug: String? { displayHandle(from: current) }

    var body: some View {
        VStack(spacing: 0) {
            TextField(String(localized: "brain.editable.changeOwner", defaultValue: "Change owner..."), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 10).padding(.vertical, 8)
                .focused($searchFocused)
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    Button(action: { onSelect(nil) }) {
                        HStack(spacing: 8) {
                            Image(systemName: "person.slash")
                                .font(.system(size: 11))
                                .foregroundColor(BVColor.fgMute)
                            Text(String(localized: "brain.editable.unassigned", defaultValue: "Unassigned"))
                                .font(.system(size: 12))
                                .foregroundColor(BVColor.fg)
                            Spacer()
                            if current == nil {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(BVColor.fgMute)
                            }
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(EditablePickerRowHoverBackground())
                    Divider()
                    if filtered.isEmpty {
                        Text(String(localized: "brain.editable.noMatches", defaultValue: "No matches"))
                            .font(.system(size: 11).italic())
                            .foregroundColor(BVColor.fgFaint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10).padding(.vertical, 8)
                    } else {
                        ForEach(filtered, id: \.self) { slug in
                            Button(action: { onSelect("people/\(slug)") }) {
                                HStack(spacing: 8) {
                                    Text(String(slug.prefix(1)).uppercased())
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundColor(.white)
                                        .frame(width: 14, height: 14)
                                        .background(Circle().fill(slugColor(slug)))
                                    Text(slug)
                                        .font(.system(size: 12))
                                        .foregroundColor(BVColor.fg)
                                    Spacer()
                                    if currentSlug == slug {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundColor(BVColor.fgMute)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .frame(height: 26)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .background(EditablePickerRowHoverBackground())
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(height: scrollHeight)
        }
        .frame(width: 240)
        .background(BVColor.bgElev)
        .onAppear { searchFocused = true }
    }

    /// Explicit height so NSHostingController.fittingSize reports the real
    /// content size to NSPanel. `maxHeight:` alone collapses to 0 in the
    /// initial layout pass, which makes the panel render as an empty sliver.
    private var scrollHeight: CGFloat {
        let rowHeight: CGFloat = 26
        // Rows: Unassigned + divider + either "No matches" or filtered slugs.
        let bodyRows = filtered.isEmpty ? 1 : filtered.count
        let totalRows = 1 + bodyRows
        let estimated = CGFloat(totalRows) * rowHeight + 8 + 1 // +divider +vpad
        return min(estimated, 240)
    }

    private func slugColor(_ slug: String) -> Color {
        BrainPersonColor.color(for: slug)
    }
}

// MARK: - Editable date badge

struct EditableDateBadge: View {
    let value: BrainDate?
    let onChange: (Date?) -> Void

    @State private var isPresented = false

    var body: some View {
        Button(action: { isPresented = true }) {
            if let value {
                let days = Calendar(identifier: .gregorian).dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: value.date)).day ?? 0
                let overdue = days < 0
                let soon = days >= 0 && days <= 3
                let color: Color = overdue ? BVColor.priorityUrgent : (soon ? BVColor.priorityHigh : BVColor.fg)
                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10))
                        .foregroundColor(color.opacity(0.7))
                    Text(absoluteString(value.date))
                        .font(.system(size: 11.5).monospacedDigit())
                        .foregroundColor(color)
                }
                .padding(.horizontal, 5).frame(height: 20)
                .contentShape(Rectangle())
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 10))
                        .foregroundColor(BVColor.fgFaint)
                    Text(String(localized: "brain.editable.setDate", defaultValue: "Set date..."))
                        .font(.system(size: 11.5).italic())
                        .foregroundColor(BVColor.fgFaint)
                }
                .padding(.horizontal, 5).frame(height: 20)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .panelPopover(isPresented: $isPresented) {
            DatePickerPopover(
                current: value?.date,
                onSelect: { newDate in
                    onChange(newDate)
                    isPresented = false
                }
            )
        }
    }

    private func absoluteString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f.string(from: d)
    }
}

private struct DatePickerPopover: View {
    let current: Date?
    let onSelect: (Date?) -> Void

    @State private var selected: Date

    init(current: Date?, onSelect: @escaping (Date?) -> Void) {
        self.current = current
        self.onSelect = onSelect
        _selected = State(initialValue: current ?? Date())
    }

    var body: some View {
        VStack(spacing: 0) {
            GraphicalDatePickerRepresentable(date: $selected)
                .padding(.horizontal, 6).padding(.top, 6).padding(.bottom, 4)
            Divider()
            HStack {
                Button(String(localized: "brain.editable.clear", defaultValue: "Clear")) {
                    onSelect(nil)
                }
                .buttonStyle(.plain)
                .foregroundColor(BVColor.fgMute)
                .font(.system(size: 11.5))
                Spacer(minLength: 8)
                Button(String(localized: "brain.editable.set", defaultValue: "Set")) {
                    onSelect(selected)
                }
                .buttonStyle(.plain)
                .foregroundColor(BVColor.accent)
                .font(.system(size: 11.5, weight: .semibold))
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
        }
        .fixedSize()
        .background(BVColor.bg)

    }
}

/// NSDatePicker wrapped so we can disable the system-drawn background.
/// SwiftUI's `DatePicker(.graphical)` paints its own chrome that doesn't
/// match the surrounding popover background; this lets the popover color
/// show through the calendar's padding region.
private struct GraphicalDatePickerRepresentable: NSViewRepresentable {
    @Binding var date: Date

    func makeNSView(context: Context) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .clockAndCalendar
        picker.datePickerElements = .yearMonthDay
        picker.drawsBackground = false
        picker.isBezeled = false
        picker.isBordered = false
        picker.focusRingType = .none
        picker.dateValue = date
        picker.target = context.coordinator
        picker.action = #selector(Coordinator.dateChanged(_:))
        return picker
    }

    func updateNSView(_ nsView: NSDatePicker, context: Context) {
        if abs(nsView.dateValue.timeIntervalSince(date)) > 0.5 {
            nsView.dateValue = date
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: GraphicalDatePickerRepresentable
        init(_ parent: GraphicalDatePickerRepresentable) { self.parent = parent }
        @objc func dateChanged(_ sender: NSDatePicker) {
            parent.date = sender.dateValue
        }
    }
}

// MARK: - Editable cadence pill

private func goalCadenceLabel(_ c: GoalCadence) -> String {
    switch c {
    case .daily: return String(localized: "brain.cadence.daily", defaultValue: "Daily")
    case .weekly: return String(localized: "brain.cadence.weekly", defaultValue: "Weekly")
    case .monthly: return String(localized: "brain.cadence.monthly", defaultValue: "Monthly")
    case .quarterly: return String(localized: "brain.cadence.quarterly", defaultValue: "Quarterly")
    }
}

struct EditableCadencePill: View {
    let rawValue: String?
    let onChange: (GoalCadence?) -> Void

    @State private var isPresented = false

    private var current: GoalCadence? {
        guard let rawValue else { return nil }
        return GoalCadence(rawValue: rawValue.lowercased())
    }

    var body: some View {
        Button(action: { isPresented = true }) {
            HStack(spacing: 5) {
                if let cadence = current {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                        .foregroundColor(BVColor.fgMute.opacity(0.8))
                    Text(goalCadenceLabel(cadence))
                        .font(.system(size: 11.5))
                        .foregroundColor(BVColor.fg)
                } else {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                        .foregroundColor(BVColor.fgFaint)
                    Text(String(localized: "brain.editable.setCadence", defaultValue: "Set cadence..."))
                        .font(.system(size: 11.5).italic())
                        .foregroundColor(BVColor.fgFaint)
                }
            }
            .inspectorPillChrome()
        }
        .buttonStyle(.plain)
        .panelPopover(isPresented: $isPresented) {
            CadencePickerView(
                current: current,
                onSelect: { newValue in
                    if newValue != current {
                        onChange(newValue)
                    }
                    isPresented = false
                }
            )
        }
    }
}

struct CadencePickerView: View {
    let current: GoalCadence?
    let onSelect: (GoalCadence?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                ForEach(Array(GoalCadence.allCases.enumerated()), id: \.element) { idx, cadence in
                    Button(action: { onSelect(cadence) }) {
                        HStack(spacing: 8) {
                            Image(systemName: "clock")
                                .font(.system(size: 11))
                                .foregroundColor(BVColor.fgMute)
                            Text(goalCadenceLabel(cadence))
                                .font(.system(size: 12))
                                .foregroundColor(BVColor.fg)
                            Spacer()
                            if current == cadence {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(BVColor.fgMute)
                            }
                            Text("\(idx + 1)")
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundColor(BVColor.fgFaint)
                                .frame(minWidth: 14, alignment: .trailing)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(EditablePickerRowHoverBackground())
                    .keyboardShortcut(KeyEquivalent(Character("\(idx + 1)")), modifiers: [])
                }
            }
            .padding(.vertical, 4)
        }
        .frame(width: 200)
        .background(BVColor.bgElev)

    }
}

// MARK: - Shared hover

struct EditablePickerRowHoverBackground: View {
    @State private var hovering = false
    var body: some View {
        Rectangle()
            .fill(hovering ? BVColor.bgHover : Color.clear)
            .onHover { hovering = $0 }
    }
}

// MARK: - PanelPopover: borderless NSPanel as a popover replacement

/// SwiftUI's `.popover` wraps NSPopover, whose rounded corners and arrow
/// are drawn by a private frame view we cannot override. `.panelPopover`
/// replaces it with a borderless NSPanel — we draw the chrome ourselves
/// (sharp corners, custom background, no arrow), and the content stays
/// SwiftUI. Behaves like a popover: anchored to a view, dismisses on
/// outside click or Escape, transient.
enum PanelPopoverAlignment {
    case center, leading, trailing
}

extension View {
    /// Drop-in replacement for `.popover(isPresented:arrowEdge:)` that
    /// uses a borderless NSPanel instead of NSPopover.
    func panelPopover<Content: View>(
        isPresented: Binding<Bool>,
        alignment: PanelPopoverAlignment = .center,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        background(PanelPopoverPresenter(isPresented: isPresented, alignment: alignment, content: content))
    }
}

/// NSPanel subclass that can take key focus while still letting the parent
/// app stay active. Standard pop-up-menu pattern — the inner TextField /
/// NSDatePicker become firstResponder, but the underlying app window
/// keeps its main/active status.
private final class PickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private struct PanelPopoverPresenter<Content: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    let alignment: PanelPopoverAlignment
    let content: () -> Content

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        context.coordinator.anchorView = view
        context.coordinator.alignment = alignment
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.anchorView = nsView
        context.coordinator.alignment = alignment
        context.coordinator.update(content: content(), isPresented: isPresented)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.dismiss()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented)
    }

    @MainActor
    final class Coordinator: NSObject {
        @Binding var isPresented: Bool
        weak var anchorView: NSView?
        var alignment: PanelPopoverAlignment = .center

        private var panel: PickerPanel?
        private var hostingController: NSHostingController<AnyView>?
        private var localMonitor: Any?
        private var globalMonitor: Any?
        private var trackingObservers: [NSObjectProtocol] = []

        init(isPresented: Binding<Bool>) {
            _isPresented = isPresented
        }

        func update(content: Content, isPresented presented: Bool) {
            if presented {
                present(content: AnyView(content))
            } else {
                dismiss()
            }
        }

        func present(content: AnyView) {
            guard let anchorView, let anchorWindow = anchorView.window else { return }

            if let hosting = hostingController {
                hosting.rootView = content
                hosting.view.layoutSubtreeIfNeeded()
                resizeAndReposition()
                return
            }

            let hosting = NSHostingController(rootView: content)
            // wantsLayer = true 가 없으면 NSPanel.hasShadow가 panel frame을
            // 따라 사각 그림자를 그려서 rounded SwiftUI content와 어긋난다
            // (사용자가 본 "사다리꼴 그림자"의 원인). 레이어 백킹을 켜면
            // 시스템이 contentView 알파 마스크 형태대로 native shadow를 그린다.
            hosting.view.wantsLayer = true
            hosting.view.layoutSubtreeIfNeeded()
            hostingController = hosting

            let panel = PickerPanel(
                contentRect: NSRect(origin: .zero, size: hosting.view.fittingSize),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = false
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .popUpMenu
            panel.animationBehavior = .utilityWindow
            panel.contentViewController = hosting
            self.panel = panel

            positionPanel(anchoredTo: anchorView, in: anchorWindow)
            panel.makeKeyAndOrderFront(nil)

            installEventMonitors()
            installAnchorTracking(for: anchorView, window: anchorWindow)
        }

        func dismiss() {
            guard panel != nil else { return }
            removeEventMonitors()
            panel?.orderOut(nil)
            panel = nil
            hostingController = nil
            // Sync binding synchronously so a fresh open in the same
            // runloop tick isn't clobbered by a delayed `false` write.
            if isPresented {
                isPresented = false
            }
        }

        // MARK: Positioning

        private func resizeAndReposition() {
            guard let hosting = hostingController, let panel else { return }
            let size = hosting.view.fittingSize
            var frame = panel.frame
            frame.size = size
            panel.setFrame(frame, display: true)
            if let anchorView, let anchorWindow = anchorView.window {
                positionPanel(anchoredTo: anchorView, in: anchorWindow)
            }
        }

        private func positionPanel(anchoredTo anchor: NSView, in anchorWindow: NSWindow) {
            guard let panel, let hosting = hostingController else { return }
            let size = hosting.view.fittingSize
            let anchorRectInWindow = anchor.convert(anchor.bounds, to: nil)
            let anchorRectInScreen = anchorWindow.convertToScreen(anchorRectInWindow)

            // Default: below the anchor, with horizontal alignment per option.
            let xOrigin: CGFloat
            switch alignment {
            case .center:   xOrigin = anchorRectInScreen.midX - size.width / 2
            case .leading:  xOrigin = anchorRectInScreen.minX
            case .trailing: xOrigin = anchorRectInScreen.maxX - size.width
            }
            var origin = NSPoint(
                x: xOrigin,
                y: anchorRectInScreen.minY - size.height - 6
            )

            // Find the screen that actually contains the anchor's midpoint
            // (not the anchor window's "dominant" screen, which can be on
            // the wrong display when the window spans monitors).
            let anchorMid = NSPoint(x: anchorRectInScreen.midX, y: anchorRectInScreen.midY)
            let screen = NSScreen.screens.first { $0.frame.contains(anchorMid) }
                ?? anchorWindow.screen
                ?? NSScreen.main
            if let visible = screen?.visibleFrame {
                origin.x = max(visible.minX + 4, min(origin.x, visible.maxX - size.width - 4))
                if origin.y < visible.minY + 4 {
                    origin.y = anchorRectInScreen.maxY + 6
                }
                origin.y = max(visible.minY + 4, min(origin.y, visible.maxY - size.height - 4))
            }
            panel.setFrameOrigin(origin)
        }

        // MARK: Event monitors

        private func installEventMonitors() {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] event in
                guard let self else { return event }
                if event.type == .keyDown && event.keyCode == 53 {
                    self.dismiss()
                    return nil
                }
                if event.type == .leftMouseDown || event.type == .rightMouseDown || event.type == .otherMouseDown {
                    if event.window !== self.panel {
                        // Anchor view 영역에 떨어진 mouseDown은 이벤트를 소비한다.
                        // 그렇지 않으면 dismiss → isPresented=false 직후 같은 클릭이
                        // Button.action까지 흘러가 다시 isPresented=true로 토글되어
                        // popover가 끊임없이 다시 열리는 버그가 생긴다. anchor 클릭은
                        // 명시적 토글 동작이므로 dismiss만 하고 이벤트는 흡수.
                        if let anchor = self.anchorView,
                           event.window === anchor.window {
                            let anchorRectInWindow = anchor.convert(anchor.bounds, to: nil)
                            if anchorRectInWindow.contains(event.locationInWindow) {
                                self.dismiss()
                                return nil
                            }
                        }
                        self.dismiss()
                    }
                }
                return event
            }
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
                self?.dismiss()
            }
            // 앱 비활성화(Cmd-Tab 등) 시 popover가 다른 앱 위에 떠 있는 채로
            // 남는 버그를 방지. panel.hidesOnDeactivate=false로 두는 이유는
            // 잠깐 NSEvent.modifierFlagsChanged 같은 상황까지 다 닫지 않기
            // 위한 것인데, 앱 자체가 비활성화되면 사용자 의도가 명확하다.
            trackingObservers.append(NotificationCenter.default.addObserver(
                forName: NSApplication.willResignActiveNotification,
                object: nil,
                queue: .main,
                using: { [weak self] _ in self?.dismiss() }
            ))
        }

        private func removeEventMonitors() {
            if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
            if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
            for obs in trackingObservers {
                NotificationCenter.default.removeObserver(obs)
            }
            trackingObservers.removeAll()
        }

        // MARK: Anchor tracking

        /// Re-position the panel whenever the anchor's screen location
        /// might change: window move/resize, plus any enclosing scroll
        /// view scrolling.
        private func installAnchorTracking(for anchor: NSView, window: NSWindow) {
            let nc = NotificationCenter.default
            let reposition: (Notification) -> Void = { [weak self] _ in
                guard let self, let anchor = self.anchorView,
                      let win = anchor.window else { return }
                self.positionPanel(anchoredTo: anchor, in: win)
            }

            trackingObservers.append(nc.addObserver(
                forName: NSWindow.didMoveNotification, object: window, queue: .main, using: reposition))
            trackingObservers.append(nc.addObserver(
                forName: NSWindow.didResizeNotification, object: window, queue: .main, using: reposition))

            // Enclosing scroll views: bounds change fires on every scroll.
            // Walk the responder chain for NSScrollView ancestors and
            // observe their content view bounds.
            var node: NSView? = anchor
            while let v = node {
                if let scroll = v as? NSScrollView {
                    let cv = scroll.contentView
                    cv.postsBoundsChangedNotifications = true
                    trackingObservers.append(nc.addObserver(
                        forName: NSView.boundsDidChangeNotification,
                        object: cv,
                        queue: .main,
                        using: reposition))
                }
                node = v.superview
            }
        }
    }
}
