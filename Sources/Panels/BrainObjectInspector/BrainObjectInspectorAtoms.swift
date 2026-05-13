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
    static let statusTodo = Color(nsColor: NSColor(srgbRed: 0x8a / 255.0, green: 0x8a / 255.0, blue: 0x8a / 255.0, alpha: 1.0))
    static let statusDoing = Color(nsColor: NSColor(srgbRed: 0x4e / 255.0, green: 0xa8 / 255.0, blue: 0xff / 255.0, alpha: 1.0))
    static let statusBlocked = Color(nsColor: NSColor(srgbRed: 0xef / 255.0, green: 0x5a / 255.0, blue: 0x5a / 255.0, alpha: 1.0))
    static let statusWaiting = Color(nsColor: NSColor(srgbRed: 0xe0 / 255.0, green: 0xb3 / 255.0, blue: 0x41 / 255.0, alpha: 1.0))
    static let statusCompleted = Color(nsColor: NSColor(srgbRed: 0x54 / 255.0, green: 0xc0 / 255.0, blue: 0x71 / 255.0, alpha: 1.0))
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

// MARK: - Status pill

struct StatusPillView: View {
    let status: BrainTaskStatus?

    var body: some View {
        guard let status else {
            return AnyView(EmptyValue())
        }
        return AnyView(
            HStack(spacing: 5) {
                StatusGlyph(status: status).frame(width: 12, height: 12)
                Text(label)
                    .font(.system(size: 11.5))
                    .foregroundColor(BVColor.fg)
            }
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(BVColor.bgInput)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(BVColor.border))
            )
            .accessibilityLabel(Text(label))
        )
    }

    private var label: String {
        switch status! {
        case .todo: return String(localized: "brain.status.todo", defaultValue: "Todo")
        case .doing: return String(localized: "brain.status.doing", defaultValue: "In progress")
        case .active: return String(localized: "brain.status.active", defaultValue: "Active")
        case .blocked: return String(localized: "brain.status.blocked", defaultValue: "Blocked")
        case .waiting: return String(localized: "brain.status.waiting", defaultValue: "Waiting")
        case .completed: return String(localized: "brain.status.completed", defaultValue: "Completed")
        case .canceled: return String(localized: "brain.status.canceled", defaultValue: "Canceled")
        }
    }
}

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
            case .todo:
                var path = Path(ellipseIn: circleRect)
                ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.2, dash: [2, 1.4]))
                _ = path
            case .doing, .active:
                ctx.stroke(Path(ellipseIn: circleRect), with: .color(color), lineWidth: 1.2)
                var fill = Path()
                fill.move(to: center)
                fill.addArc(center: center, radius: r - 1, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
                fill.closeSubpath()
                ctx.fill(fill, with: .color(color))
            case .blocked:
                ctx.fill(Path(ellipseIn: circleRect), with: .color(color))
                var x = Path()
                let inset: CGFloat = 3
                x.move(to: CGPoint(x: circleRect.minX + inset, y: circleRect.minY + inset))
                x.addLine(to: CGPoint(x: circleRect.maxX - inset, y: circleRect.maxY - inset))
                x.move(to: CGPoint(x: circleRect.maxX - inset, y: circleRect.minY + inset))
                x.addLine(to: CGPoint(x: circleRect.minX + inset, y: circleRect.maxY - inset))
                ctx.stroke(x, with: .color(Color(nsColor: .black).opacity(0.85)), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
            case .waiting:
                ctx.fill(Path(ellipseIn: circleRect), with: .color(color))
                for dx in [-2.4, 0.0, 2.4] {
                    let dot = CGRect(x: center.x + CGFloat(dx) - 0.8, y: center.y - 0.8, width: 1.6, height: 1.6)
                    ctx.fill(Path(ellipseIn: dot), with: .color(Color(nsColor: .black).opacity(0.85)))
                }
            case .completed:
                ctx.fill(Path(ellipseIn: circleRect), with: .color(color))
                var check = Path()
                check.move(to: CGPoint(x: center.x - 2.4, y: center.y + 0.0))
                check.addLine(to: CGPoint(x: center.x - 0.8, y: center.y + 1.6))
                check.addLine(to: CGPoint(x: center.x + 2.4, y: center.y - 1.6))
                ctx.stroke(check, with: .color(Color(nsColor: NSColor(srgbRed: 0.05, green: 0.13, blue: 0.08, alpha: 1.0))),
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
        case .todo: return BVColor.statusTodo
        case .doing: return BVColor.statusDoing
        case .active: return BVColor.statusCompleted
        case .blocked: return BVColor.statusBlocked
        case .waiting: return BVColor.statusWaiting
        case .completed: return BVColor.statusCompleted
        case .canceled: return BVColor.statusCanceled
        }
    }
}

// MARK: - Priority pill

struct PriorityPillView: View {
    let priority: BrainPriority?

    var body: some View {
        guard let priority else {
            return AnyView(EmptyValue())
        }
        let color = color(for: priority)
        return AnyView(
            HStack(spacing: 5) {
                if priority == .urgent {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(color)
                } else {
                    PriorityBars(level: barLevel(for: priority), color: color)
                }
                Text(label(for: priority))
                    .font(.system(size: 11.5))
                    .foregroundColor(BVColor.fg)
            }
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(BVColor.bgInput)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(BVColor.border))
            )
            .accessibilityLabel(Text(label(for: priority)))
        )
    }

    private func barLevel(for p: BrainPriority) -> Int {
        switch p { case .urgent: return 3; case .high: return 3; case .normal: return 2; case .low: return 1 }
    }
    private func color(for p: BrainPriority) -> Color {
        switch p {
        case .urgent: return BVColor.priorityUrgent
        case .high: return BVColor.priorityHigh
        case .normal: return BVColor.priorityNormal
        case .low: return BVColor.priorityLow
        }
    }
    private func label(for p: BrainPriority) -> String {
        switch p {
        case .urgent: return String(localized: "brain.priority.urgent", defaultValue: "Urgent")
        case .high: return String(localized: "brain.priority.high", defaultValue: "High")
        case .normal: return String(localized: "brain.priority.normal", defaultValue: "Normal")
        case .low: return String(localized: "brain.priority.low", defaultValue: "Low")
        }
    }
}

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

// MARK: - Person chip

struct PersonChipView: View {
    let handle: String?

    var body: some View {
        guard let handle, !handle.isEmpty else {
            return AnyView(EmptyValue())
        }
        let initial = String(handle.prefix(1)).uppercased()
        let color = colorFor(handle: handle)
        return AnyView(
            HStack(spacing: 6) {
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
            .accessibilityLabel(Text(handle))
        )
    }

    /// Stable per-handle color, matching the prototype's hard-coded
    /// PERSON_COLORS map for the common handles and falling back to a
    /// hash-derived hue for everyone else.
    private func colorFor(handle: String) -> Color {
        let known: [String: Color] = [
            "dan": Color(nsColor: NSColor(srgbRed: 0x5b / 255, green: 0x9d / 255, blue: 0xf9 / 255, alpha: 1)),
            "leo": Color(nsColor: NSColor(srgbRed: 0xc1 / 255, green: 0x84 / 255, blue: 0xe0 / 255, alpha: 1)),
            "alex": Color(nsColor: NSColor(srgbRed: 0x54 / 255, green: 0xc0 / 255, blue: 0x71 / 255, alpha: 1)),
            "sam": Color(nsColor: NSColor(srgbRed: 0xe0 / 255, green: 0xb3 / 255, blue: 0x41 / 255, alpha: 1)),
            "pat": Color(nsColor: NSColor(srgbRed: 0xf0 / 255, green: 0x8a / 255, blue: 0x3e / 255, alpha: 1)),
            "mira": Color(nsColor: NSColor(srgbRed: 0xef / 255, green: 0x5a / 255, blue: 0x5a / 255, alpha: 1)),
        ]
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
    var body: some View {
        if tags.isEmpty {
            EmptyValue()
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

// MARK: - Editable Goal status pill

/// Visual glyph for a `GoalStatus`. Reuses `StatusGlyph`'s `BrainTaskStatus`
/// rendering via a small mapping so the editable Goal pill matches the
/// read-only Task pill style.
private func glyphMapping(_ s: GoalStatus) -> BrainTaskStatus {
    switch s {
    case .active: return .active
    case .blocked: return .blocked
    case .draft: return .todo
    case .completed: return .completed
    }
}

private func goalStatusLabel(_ s: GoalStatus) -> String {
    switch s {
    case .active: return String(localized: "brain.goal.status.active", defaultValue: "Active")
    case .blocked: return String(localized: "brain.goal.status.blocked", defaultValue: "Blocked")
    case .draft: return String(localized: "brain.goal.status.draft", defaultValue: "Draft")
    case .completed: return String(localized: "brain.goal.status.completed", defaultValue: "Completed")
    }
}

struct EditableGoalStatusPill: View {
    let value: GoalStatus?
    let onChange: (GoalStatus?) -> Void

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
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(BVColor.bgInput)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(BVColor.border))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            GoalStatusPickerView(
                current: value,
                onSelect: { newValue in
                    if newValue != value {
                        onChange(newValue)
                    }
                    isPresented = false
                }
            )
        }
        .accessibilityLabel(Text(value.map(goalStatusLabel) ?? String(localized: "brain.editable.setStatus", defaultValue: "Set status...")))
    }
}

struct GoalStatusPickerView: View {
    let current: GoalStatus?
    let onSelect: (GoalStatus?) -> Void

    @State private var query: String = ""
    @FocusState private var searchFocused: Bool

    private var filtered: [GoalStatus] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return GoalStatus.allCases }
        return GoalStatus.allCases.filter { goalStatusLabel($0).lowercased().hasPrefix(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField(String(localized: "brain.editable.changeStatus", defaultValue: "Change status..."), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 10).padding(.vertical, 8)
                .focused($searchFocused)
                .onSubmit {
                    if let first = filtered.first { onSelect(first) }
                }
            Divider()
            VStack(spacing: 0) {
                ForEach(Array(filtered.enumerated()), id: \.element) { idx, status in
                    Button(action: { onSelect(status) }) {
                        HStack(spacing: 8) {
                            StatusGlyph(status: glyphMapping(status)).frame(width: 14, height: 14)
                            Text(goalStatusLabel(status))
                                .font(.system(size: 12))
                                .foregroundColor(BVColor.fg)
                            Spacer()
                            if current == status {
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
                if filtered.isEmpty {
                    Text(String(localized: "brain.editable.noMatches", defaultValue: "No matches"))
                        .font(.system(size: 11).italic())
                        .foregroundColor(BVColor.fgFaint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 8)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(width: 240)
        .background(BVColor.bgElev)
        .onAppear { searchFocused = true }
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
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
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
        var hasher = Hasher(); hasher.combine(handle)
        let h = abs(hasher.finalize())
        let hue = Double(h % 360) / 360.0
        return Color(hue: hue, saturation: 0.55, brightness: 0.78)
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
            .frame(maxHeight: 240)
        }
        .frame(width: 240)
        .background(BVColor.bgElev)
        .onAppear { searchFocused = true }
    }

    private func slugColor(_ slug: String) -> Color {
        var hasher = Hasher(); hasher.combine(slug)
        let h = abs(hasher.finalize())
        let hue = Double(h % 360) / 360.0
        return Color(hue: hue, saturation: 0.55, brightness: 0.78)
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
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
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
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(BVColor.bgInput)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(BVColor.border))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
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

private struct EditablePickerRowHoverBackground: View {
    @State private var hovering = false
    var body: some View {
        Rectangle()
            .fill(hovering ? BVColor.bgHover : Color.clear)
            .onHover { hovering = $0 }
    }
}
