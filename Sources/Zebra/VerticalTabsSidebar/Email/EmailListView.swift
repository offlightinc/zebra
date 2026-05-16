import SwiftUI

struct EmailThreadItem: Identifiable, Hashable {
    let id: String
    let subject: String
    let senderName: String
    let receivedAt: Date
    let unread: Bool
    let starred: Bool
    let hasAttachment: Bool
    let labelIds: [String]
    let category: EmailCategory?

    var initial: String {
        senderName.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() } ?? "?"
    }
}

struct EmailUserLabel: Identifiable, Equatable {
    let id: String
    let name: String
    let color: Color
}

enum EmailCategory: String, CaseIterable, Hashable {
    case primary, updates, promotions, social, forums, purchases

    var label: String {
        switch self {
        case .primary: return String(localized: "email.category.primary", defaultValue: "기본")
        case .updates: return String(localized: "email.category.updates", defaultValue: "업데이트")
        case .promotions: return String(localized: "email.category.promotions", defaultValue: "프로모션")
        case .social: return String(localized: "email.category.social", defaultValue: "소셜")
        case .forums: return String(localized: "email.category.forums", defaultValue: "포럼")
        case .purchases: return String(localized: "email.category.purchases", defaultValue: "구매")
        }
    }
}

enum EmailTimeBucket: String, CaseIterable, Hashable {
    case today, yesterday, week, older

    var label: String {
        switch self {
        case .today: return String(localized: "email.group.today", defaultValue: "오늘")
        case .yesterday: return String(localized: "email.group.yesterday", defaultValue: "어제")
        case .week: return String(localized: "email.group.week", defaultValue: "이번 주")
        case .older: return String(localized: "email.group.older", defaultValue: "이전")
        }
    }

    static func bucket(for date: Date, now: Date = Date()) -> EmailTimeBucket {
        let cal = Calendar.current
        if cal.isDate(date, inSameDayAs: now) { return .today }
        if let yesterday = cal.date(byAdding: .day, value: -1, to: now),
           cal.isDate(date, inSameDayAs: yesterday) {
            return .yesterday
        }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: now)).day ?? 0
        return days < 7 ? .week : .older
    }
}

enum EmailFilterField: String, CaseIterable, Hashable, Sendable {
    case unread, starred, attachment, time, label

    var label: String {
        switch self {
        case .unread: return String(localized: "email.filter.read", defaultValue: "읽음")
        case .starred: return String(localized: "email.filter.starred", defaultValue: "별표")
        case .attachment: return String(localized: "email.filter.attachment", defaultValue: "첨부")
        case .time: return String(localized: "email.filter.time", defaultValue: "시간")
        case .label: return String(localized: "email.filter.label", defaultValue: "라벨")
        }
    }
}

enum EmailFilterOp: Hashable, Sendable {
    case `is`, isNot
    var symbol: String { self == .is ? "=" : "≠" }
}

struct EmailFilter: Identifiable, Hashable, Sendable {
    let field: EmailFilterField
    var op: EmailFilterOp
    var values: [String]

    var id: EmailFilterField { field }
}

enum EmailFilterPopoverStep: Equatable {
    case field
    case value(EmailFilterField)
}

@MainActor
final class EmailListViewModel: ObservableObject {
    @Published var filters: [EmailFilter] = []

    func setFilter(_ filter: EmailFilter) {
        if let idx = filters.firstIndex(where: { $0.field == filter.field }) {
            filters[idx] = filter
        } else {
            filters.append(filter)
        }
    }

    func removeFilter(field: EmailFilterField) {
        filters.removeAll { $0.field == field }
    }

    static func applyFilters(_ threads: [EmailThreadItem], _ filters: [EmailFilter]) -> [EmailThreadItem] {
        guard !filters.isEmpty else { return threads }
        return threads.filter { thread in
            filters.allSatisfy { filter in
                if filter.values.isEmpty { return true }
                let current = currentValues(for: thread, field: filter.field)
                let matched = current.contains { filter.values.contains($0) }
                return filter.op == .is ? matched : !matched
            }
        }
    }

    static func groups(for threads: [EmailThreadItem]) -> [(bucket: EmailTimeBucket, items: [EmailThreadItem])] {
        EmailTimeBucket.allCases.compactMap { bucket in
            let items = threads
                .filter { EmailTimeBucket.bucket(for: $0.receivedAt) == bucket }
                .sorted { $0.receivedAt > $1.receivedAt }
            return items.isEmpty ? nil : (bucket, items)
        }
    }

    private static func currentValues(for thread: EmailThreadItem, field: EmailFilterField) -> [String] {
        switch field {
        case .unread: return [thread.unread ? "yes" : "no"]
        case .starred: return [thread.starred ? "yes" : "no"]
        case .attachment: return [thread.hasAttachment ? "yes" : "no"]
        case .time: return [EmailTimeBucket.bucket(for: thread.receivedAt).rawValue]
        case .label:
            return thread.labelIds + (thread.category.map { ["category:\($0.rawValue)"] } ?? [])
        }
    }
}

struct EmailListView: View {
    let threads: [EmailThreadItem]
    @State private var localUserLabels: [EmailUserLabel]
    let onCreateLabel: (String) -> EmailUserLabel
    @StateObject private var viewModel = EmailListViewModel()
    @State private var filterStep: EmailFilterPopoverStep?

    init(
        threads: [EmailThreadItem],
        userLabels: [EmailUserLabel],
        onCreateLabel: @escaping (String) -> EmailUserLabel
    ) {
        self.threads = threads
        self.onCreateLabel = onCreateLabel
        _localUserLabels = State(initialValue: userLabels)
    }

    init(threads: [EmailThreadItem], initialUserLabels: [EmailUserLabel]) {
        self.init(
            threads: threads,
            userLabels: initialUserLabels,
            onCreateLabel: { name in
                EmailUserLabel(id: "local-\(UUID().uuidString)", name: name, color: BrainPersonColor.color(for: name))
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            topAlignmentRow
            EmailListToolbar(
                existingFilterFields: Set(viewModel.filters.map(\.field)),
                filterStep: $filterStep,
                currentFilter: { field in
                    viewModel.filters.first(where: { $0.field == field })
                        ?? EmailFilter(field: field, op: .is, values: [])
                },
                userLabels: localUserLabels,
                onPickField: { field in
                    if !viewModel.filters.contains(where: { $0.field == field }) {
                        viewModel.filters.append(EmailFilter(field: field, op: .is, values: []))
                    }
                },
                onChangeFilterValues: { viewModel.setFilter($0) },
                onCreateLabel: { name in
                    let label = onCreateLabel(name)
                    localUserLabels.append(label)
                    return label
                },
                onCloseFilter: {}
            )
            .frame(height: SidebarWorkspaceListMetrics.secondRowHeight)

            if !viewModel.filters.isEmpty {
                chipRow
            }

            listScrollView
        }
        .background(BVColor.bg)
    }

    private var topAlignmentRow: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .frame(height: SidebarWorkspaceListMetrics.firstRowTopOffset)
    }

    private var chipRow: some View {
        TaskChipFlowLayout(spacing: 5) {
            ForEach(viewModel.filters) { filter in
                EmailFilterChipView(
                    filter: filter,
                    userLabels: localUserLabels,
                    isOpen: filterStep == .value(filter.field),
                    onEdit: { filterStep = .value(filter.field) },
                    onRemove: { viewModel.removeFilter(field: filter.field) }
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BVColor.bg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(BVColor.border).frame(height: 1)
        }
    }

    private var listScrollView: some View {
        let filtered = EmailListViewModel.applyFilters(threads, viewModel.filters)
        let groups = EmailListViewModel.groups(for: filtered)
        return ScrollView {
            LazyVStack(spacing: 0) {
                if groups.isEmpty {
                    placeholder(String(localized: "email.list.empty.filtered", defaultValue: "조건에 맞는 메일이 없습니다"))
                } else {
                    ForEach(groups, id: \.bucket) { group in
                        SidebarSectionHeader(
                            label: group.bucket.label,
                            count: group.items.count,
                            isCollapsed: false,
                            onToggle: nil
                        )
                        ForEach(group.items) { thread in
                            EmailThreadRow(thread: thread)
                        }
                    }
                }
            }
            .padding(.bottom, 12)
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(BVColor.fgFaint)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 48)
    }

}

struct EmailSidebarView: View {
    let threads: [EmailThreadItem]
    let userLabels: [EmailUserLabel]
    let onCreateLabel: (String) -> EmailUserLabel

    var body: some View {
        EmailListView(
            threads: threads,
            userLabels: userLabels,
            onCreateLabel: onCreateLabel
        )
    }
}

private struct EmailListToolbar: View {
    let existingFilterFields: Set<EmailFilterField>
    @Binding var filterStep: EmailFilterPopoverStep?
    let currentFilter: (EmailFilterField) -> EmailFilter
    let userLabels: [EmailUserLabel]
    let onPickField: (EmailFilterField) -> Void
    let onChangeFilterValues: (EmailFilter) -> Void
    let onCreateLabel: (String) -> EmailUserLabel
    let onCloseFilter: () -> Void

    @State private var filterHover = false

    var body: some View {
        HStack(spacing: 8) {
            Button(action: toggleFilterPopover) {
                HStack(spacing: 5) {
                    FilterFunnelIcon().frame(width: 12, height: 12)
                    Text(String(localized: "email.toolbar.filter", defaultValue: "필터"))
                        .font(.system(size: 11.5))
                }
                .foregroundColor(BVColor.fgMute)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(filterHover ? BVColor.bgHover : Color.clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { filterHover = $0 }
            .panelPopover(isPresented: filterPopoverPresented, alignment: .leading) {
                filterPopoverContent
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(BVColor.bg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(BVColor.border).frame(height: 1)
        }
    }

    private func toggleFilterPopover() {
        if filterStep == nil {
            filterStep = .field
        } else {
            onCloseFilter()
            filterStep = nil
        }
    }

    private var filterPopoverPresented: Binding<Bool> {
        Binding(
            get: { filterStep != nil },
            set: { newValue in
                if !newValue {
                    onCloseFilter()
                    filterStep = nil
                }
            }
        )
    }

    @ViewBuilder
    private var filterPopoverContent: some View {
        switch filterStep {
        case .field, .none:
            EmailFilterFieldPicker(existingFields: existingFilterFields) { field in
                onPickField(field)
                filterStep = .value(field)
            }
        case .value(let field):
            EmailFilterValuePicker(
                field: field,
                current: currentFilter(field),
                userLabels: userLabels,
                onCreateLabel: onCreateLabel,
                onChange: onChangeFilterValues
            )
            .id(field)
        }
    }
}

private struct EmailFilterFieldPicker: View {
    let existingFields: Set<EmailFilterField>
    let onSelect: (EmailFilterField) -> Void

    var body: some View {
        PickerContainer(title: String(localized: "email.filter.add", defaultValue: "필터 추가"), width: 200) {
            ForEach(EmailFilterField.allCases, id: \.self) { field in
                PickerRow(
                    glyph: { EmptyView() },
                    label: field.label,
                    isCurrent: false,
                    keyLabel: existingFields.contains(field) ? String(localized: "email.filter.edit", defaultValue: "수정") : nil,
                    action: { onSelect(field) },
                    omitGlyph: true
                )
            }
        }
    }
}

private struct EmailFilterValuePicker: View {
    let field: EmailFilterField
    let current: EmailFilter
    let userLabels: [EmailUserLabel]
    let onCreateLabel: (String) -> EmailUserLabel
    let onChange: (EmailFilter) -> Void

    @State private var workingValues: [String]
    @State private var workingOp: EmailFilterOp
    @State private var isAddingLabel = false
    @State private var draftLabelName = ""
    @FocusState private var labelFieldFocused: Bool

    init(
        field: EmailFilterField,
        current: EmailFilter,
        userLabels: [EmailUserLabel],
        onCreateLabel: @escaping (String) -> EmailUserLabel,
        onChange: @escaping (EmailFilter) -> Void
    ) {
        self.field = field
        self.current = current
        self.userLabels = userLabels
        self.onCreateLabel = onCreateLabel
        self.onChange = onChange
        _workingValues = State(initialValue: current.values)
        _workingOp = State(initialValue: current.op)
    }

    var body: some View {
        PickerContainer(title: "\(field.label) \(workingOp.symbol)", width: 220) {
            valueRows

            Divider().padding(.vertical, 4)

            Button(action: toggleOp) {
                HStack {
                    Text(workingOp == .is
                        ? String(localized: "email.filter.useIsNot", defaultValue: "\"아님\" 사용")
                        : String(localized: "email.filter.useIs", defaultValue: "\"일치\" 사용"))
                        .font(.system(size: 11.5))
                        .foregroundColor(BVColor.fgMute)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .frame(height: 24)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private var valueRows: some View {
        switch field {
        case .unread:
            binaryRows(yes: String(localized: "email.filter.unread", defaultValue: "읽지 않음"), no: String(localized: "email.filter.readValue", defaultValue: "읽음"))
        case .starred, .attachment:
            binaryRows(yes: String(localized: "email.filter.exists", defaultValue: "있음"), no: String(localized: "email.filter.none", defaultValue: "없음"))
        case .time:
            ForEach(EmailTimeBucket.allCases, id: \.self) { bucket in
                row(raw: bucket.rawValue, label: bucket.label) {
                    Image(systemName: "clock")
                        .font(.system(size: 11))
                        .foregroundColor(BVColor.fgMute)
                }
            }
        case .label:
            labelRows
        }
    }

    private func binaryRows(yes: String, no: String) -> some View {
        Group {
            row(raw: "yes", label: yes) { EmptyView() }
            row(raw: "no", label: no) { EmptyView() }
        }
    }

    @ViewBuilder
    private var labelRows: some View {
        PickerSectionLabel(text: String(localized: "email.filter.userLabels", defaultValue: "사용자 라벨"))
        ForEach(userLabels) { label in
            row(raw: label.id, label: label.name) {
                Circle().fill(label.color).frame(width: 9, height: 9)
            }
        }
        if isAddingLabel {
            TextField(String(localized: "email.filter.newLabelPlaceholder", defaultValue: "새 라벨"), text: $draftLabelName)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundColor(BVColor.fg)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(BVColor.bgInput)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(BVColor.accent.opacity(0.45)))
                )
                .padding(.horizontal, 4)
                .focused($labelFieldFocused)
                .onSubmit(commitNewLabel)
                .onExitCommand(perform: cancelNewLabel)
        } else {
            PickerRow(
                glyph: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(BVColor.fgMute)
                },
                label: String(localized: "email.filter.newLabel", defaultValue: "새 라벨"),
                isCurrent: false,
                keyLabel: nil,
                action: {
                    isAddingLabel = true
                    DispatchQueue.main.async { labelFieldFocused = true }
                }
            )
        }
        PickerSectionLabel(text: String(localized: "email.filter.autoCategories", defaultValue: "자동 카테고리"))
        ForEach(EmailCategory.allCases, id: \.self) { category in
            row(raw: "category:\(category.rawValue)", label: category.label) {
                Image(systemName: "tray")
                    .font(.system(size: 10))
                    .foregroundColor(BVColor.fgFaint)
            }
        }
    }

    private func row<Glyph: View>(raw: String, label: String, @ViewBuilder glyph: @escaping () -> Glyph) -> some View {
        let selected = workingValues.contains(raw)
        return PickerRow(
            glyph: glyph,
            label: label,
            isCurrent: selected,
            keyLabel: nil,
            action: { toggle(raw) },
            multiSelectChecked: selected
        )
    }

    private func toggle(_ raw: String) {
        if let idx = workingValues.firstIndex(of: raw) {
            workingValues.remove(at: idx)
        } else {
            workingValues.append(raw)
        }
        pushChange()
    }

    private func toggleOp() {
        workingOp = workingOp == .is ? .isNot : .is
        pushChange()
    }

    private func commitNewLabel() {
        let name = draftLabelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            cancelNewLabel()
            return
        }
        let label = onCreateLabel(name)
        if !workingValues.contains(label.id) {
            workingValues.append(label.id)
        }
        draftLabelName = ""
        isAddingLabel = false
        pushChange()
    }

    private func cancelNewLabel() {
        draftLabelName = ""
        isAddingLabel = false
    }

    private func pushChange() {
        var copy = current
        copy.values = workingValues
        copy.op = workingOp
        onChange(copy)
    }
}

private struct PickerSectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.42)
            .foregroundColor(BVColor.fgFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 3)
    }
}

private struct EmailFilterChipView: View {
    let filter: EmailFilter
    let userLabels: [EmailUserLabel]
    let isOpen: Bool
    let onEdit: () -> Void
    let onRemove: () -> Void

    @State private var closeHover = false

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onEdit) {
                HStack(spacing: 4) {
                    Text(filter.field.label).foregroundColor(BVColor.fgMute)
                    Text(filter.op.symbol)
                        .foregroundColor(BVColor.fgFaint)
                        .padding(.horizontal, 2)
                    Text(valueLabel)
                        .foregroundColor(filter.values.isEmpty ? BVColor.fgFaint : BVColor.fg)
                        .italic(filter.values.isEmpty)
                        .lineLimit(1)
                        .frame(maxWidth: 140, alignment: .leading)
                }
                .font(.system(size: 11.5))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(closeHover ? BVColor.fg : BVColor.fgFaint)
                    .frame(width: 14, height: 14)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(closeHover ? BVColor.bgHover : Color.clear)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { closeHover = $0 }
        }
        .padding(.leading, 7)
        .padding(.trailing, 2)
        .frame(height: 22)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isOpen ? BVColor.accent.opacity(0.16) : BVColor.bgInput)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isOpen ? BVColor.accent.opacity(0.3) : BVColor.border)
                )
        )
    }

    private var valueLabel: String {
        if filter.values.isEmpty {
            return String(localized: "email.filter.empty", defaultValue: "선택")
        }
        let displayed = filter.values.prefix(2).map(rawValueLabel).joined(separator: ", ")
        let extra = filter.values.count > 2 ? " +\(filter.values.count - 2)" : ""
        return displayed + extra
    }

    private func rawValueLabel(_ raw: String) -> String {
        switch filter.field {
        case .unread:
            return raw == "yes"
                ? String(localized: "email.filter.unread", defaultValue: "읽지 않음")
                : String(localized: "email.filter.readValue", defaultValue: "읽음")
        case .starred, .attachment:
            return raw == "yes"
                ? String(localized: "email.filter.exists", defaultValue: "있음")
                : String(localized: "email.filter.none", defaultValue: "없음")
        case .time:
            return EmailTimeBucket(rawValue: raw)?.label ?? raw
        case .label:
            if let categoryRaw = raw.removingPrefix("category:"),
               let category = EmailCategory(rawValue: categoryRaw) {
                return category.label
            }
            return userLabels.first(where: { $0.id == raw })?.name ?? raw
        }
    }
}

private struct EmailThreadRow: View {
    let thread: EmailThreadItem
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 10) {
            AvatarDot(initial: thread.initial, color: BrainPersonColor.color(for: thread.senderName))
                .frame(width: 18, height: 18)

            Text(thread.subject)
                .font(.system(size: 13.5, weight: thread.unread ? .semibold : .regular))
                .foregroundColor(thread.unread ? BVColor.fg : BVColor.fg.opacity(0.65))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 6)

            HStack(spacing: 6) {
                if thread.starred {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                        .foregroundColor(Color(nsColor: NSColor(srgbRed: 0.96, green: 0.72, blue: 0.33, alpha: 1)))
                        .frame(width: 12, height: 12)
                }
                if thread.hasAttachment {
                    Image(systemName: "paperclip")
                        .font(.system(size: 9))
                        .foregroundColor(BVColor.fgMute)
                        .frame(width: 12, height: 12)
                }
                Text(relativeTime(thread.receivedAt))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundColor(BVColor.fgFaint)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background(hovered ? BVColor.bgHover : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .accessibilityElement(children: .combine)
    }

    private func relativeTime(_ date: Date) -> String {
        let diff = max(0, Date().timeIntervalSince(date))
        if diff < 3600 { return "\(max(1, Int(diff / 60)))m" }
        if diff < 86_400 { return "\(Int(diff / 3600))h" }
        if diff < 604_800 { return "\(Int(diff / 86_400))d" }
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }
}

private struct AvatarDot: View {
    let initial: String
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .overlay(
                Text(initial)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
            )
    }
}

enum EmailSidebarSampleData {
    static let labels: [EmailUserLabel] = [
        EmailUserLabel(id: "sales", name: "Sales", color: BVColor.statusCompleted),
        EmailUserLabel(id: "billing", name: "Billing", color: BVColor.priorityHigh),
        EmailUserLabel(id: "design", name: "Design", color: BVColor.statusDoing),
        EmailUserLabel(id: "personal", name: "Personal", color: BVColor.statusCompleted.opacity(0.75)),
        EmailUserLabel(id: "news", name: "Newsletter", color: BVColor.priorityUrgent.opacity(0.75)),
    ]

    static var threads: [EmailThreadItem] {
        let now = Date()
        return [
            EmailThreadItem(id: "e1", subject: "May sprint kickoff", senderName: "Sarah Chen", receivedAt: now.addingTimeInterval(-5 * 60), unread: true, starred: true, hasAttachment: false, labelIds: ["sales"], category: .primary),
            EmailThreadItem(id: "e2", subject: "Re: Design token pass", senderName: "Marcus Lee", receivedAt: now.addingTimeInterval(-42 * 60), unread: false, starred: false, hasAttachment: true, labelIds: ["design"], category: .primary),
            EmailThreadItem(id: "e3", subject: "May invoice — Stripe", senderName: "Stripe", receivedAt: now.addingTimeInterval(-3 * 3600), unread: true, starred: false, hasAttachment: true, labelIds: ["billing"], category: .updates),
            EmailThreadItem(id: "e4", subject: "[GitHub] PR #482", senderName: "GitHub", receivedAt: now.addingTimeInterval(-26 * 3600), unread: false, starred: false, hasAttachment: false, labelIds: [], category: .updates),
            EmailThreadItem(id: "e5", subject: "Lunch Friday?", senderName: "Alex", receivedAt: now.addingTimeInterval(-2 * 86_400), unread: true, starred: false, hasAttachment: false, labelIds: ["personal"], category: .primary),
            EmailThreadItem(id: "e6", subject: "Q3 OKR draft", senderName: "Hannah", receivedAt: now.addingTimeInterval(-3 * 86_400), unread: false, starred: true, hasAttachment: true, labelIds: ["sales", "design"], category: .primary),
            EmailThreadItem(id: "e7", subject: "Weekly design notes #47", senderName: "Smashing", receivedAt: now.addingTimeInterval(-4 * 86_400), unread: false, starred: false, hasAttachment: false, labelIds: ["news"], category: .promotions),
            EmailThreadItem(id: "e8", subject: "Your April workspace summary", senderName: "Zebra", receivedAt: now.addingTimeInterval(-11 * 86_400), unread: false, starred: false, hasAttachment: true, labelIds: [], category: .updates),
        ]
    }
}

private extension String {
    func removingPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}

#if DEBUG
#Preview {
    EmailListView(
        threads: EmailSidebarSampleData.threads,
        userLabels: EmailSidebarSampleData.labels,
        onCreateLabel: { name in
            EmailUserLabel(id: "local-\(UUID().uuidString)", name: name, color: BrainPersonColor.color(for: name))
        }
    )
    .frame(width: 344, height: 760)
}
#endif
