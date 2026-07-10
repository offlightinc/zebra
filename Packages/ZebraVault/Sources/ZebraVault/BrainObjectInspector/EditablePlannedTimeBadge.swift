import SwiftUI

struct EditablePlannedTimeBadge: View {
    let start: Date?
    let end: Date?
    let hasInvalidInterval: Bool
    let onChange: (Date?, Date?) -> Void

    @State private var isPresented = false

    var body: some View {
        Button(action: { isPresented = true }) {
            HStack(spacing: 5) {
                Image(systemName: hasInvalidInterval ? "exclamationmark.triangle" : "calendar.badge.clock")
                    .font(.system(size: 10))
                    .foregroundColor(hasInvalidInterval ? BVColor.priorityHigh : BVColor.fgFaint)
                Text(label)
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundColor(hasInvalidInterval ? BVColor.priorityHigh : valueColor)
                    .lineLimit(1)
            }
            .inspectorPillChrome()
        }
        .buttonStyle(.plain)
        .panelPopover(isPresented: $isPresented) {
            TodayPlannedTimePopover(start: start, end: end) { newStart, newEnd in
                onChange(newStart, newEnd)
                isPresented = false
            }
        }
    }

    private var valueColor: Color {
        start != nil && end != nil ? BVColor.fg : BVColor.fgFaint
    }

    private var label: String {
        if hasInvalidInterval {
            return String(localized: "task.plan.invalid", defaultValue: "Invalid planned time")
        }
        guard let start, let end else {
            return String(localized: "task.plan.today.set", defaultValue: "Plan today...")
        }
        let time = DateFormatter()
        time.locale = .current
        time.setLocalizedDateFormatFromTemplate("jmm")
        if Calendar.current.isDateInToday(start) {
            return "\(time.string(from: start))–\(time.string(from: end))"
        }
        let day = DateFormatter()
        day.locale = .current
        day.setLocalizedDateFormatFromTemplate("MMM d")
        return "\(day.string(from: start)) · \(time.string(from: start))–\(time.string(from: end))"
    }
}

private struct TodayPlannedTimePopover: View {
    let onCommit: (Date?, Date?) -> Void

    @State private var selectedStart: Date
    @State private var selectedEnd: Date

    init(start: Date?, end: Date?, now: Date = Date(), onCommit: @escaping (Date?, Date?) -> Void) {
        self.onCommit = onCommit
        let calendar = Calendar.current
        let nextHalfHour = Date(timeIntervalSince1970: ceil(now.timeIntervalSince1970 / 1800) * 1800)
        let initialStart = start.flatMap { calendar.isDateInToday($0) ? $0 : nil } ?? nextHalfHour
        let initialEnd = end.flatMap { candidate in
            calendar.isDateInToday(candidate) && candidate > initialStart ? candidate : nil
        } ?? initialStart.addingTimeInterval(3600)
        _selectedStart = State(initialValue: initialStart)
        _selectedEnd = State(initialValue: initialEnd)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "task.plan.today.title", defaultValue: "Plan for today"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(BVColor.fg)
                Spacer(minLength: 12)
                Text(todayLabel)
                    .font(.system(size: 10.5))
                    .foregroundColor(BVColor.fgMute)
            }

            timeRow(
                label: String(localized: "task.plan.today.start", defaultValue: "Start"),
                selection: $selectedStart
            )
            timeRow(
                label: String(localized: "task.plan.today.end", defaultValue: "End"),
                selection: $selectedEnd
            )

            if !isValid {
                Text(String(localized: "task.plan.today.invalidRange", defaultValue: "End time must be after start time."))
                    .font(.system(size: 10.5))
                    .foregroundColor(BVColor.priorityHigh)
            }

            Divider()
            HStack {
                Button(String(localized: "task.plan.today.clear", defaultValue: "Remove plan")) {
                    onCommit(nil, nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundColor(BVColor.fgMute)
                Spacer(minLength: 12)
                Button(String(localized: "task.plan.today.save", defaultValue: "Save")) {
                    guard let interval else { return }
                    onCommit(interval.start, interval.end)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(isValid ? BVColor.accent : BVColor.fgFaint)
                .disabled(!isValid)
            }
        }
        .padding(12)
        .frame(width: 250)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(BVColor.bgElev)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(BVColor.borderStrong, lineWidth: 1)
        )
    }

    private func timeRow(label: String, selection: Binding<Date>) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundColor(BVColor.fgMute)
            Spacer(minLength: 12)
            DatePicker("", selection: selection, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.field)
                .frame(width: 92)
        }
    }

    private var todayLabel: String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMM d E")
        return formatter.string(from: Date())
    }

    private var interval: DateInterval? {
        var calendar = Calendar.current
        calendar.timeZone = .current
        let today = calendar.dateComponents([.year, .month, .day], from: Date())
        let startTime = calendar.dateComponents([.hour, .minute], from: selectedStart)
        let endTime = calendar.dateComponents([.hour, .minute], from: selectedEnd)
        var startComponents = today
        startComponents.hour = startTime.hour
        startComponents.minute = startTime.minute
        var endComponents = today
        endComponents.hour = endTime.hour
        endComponents.minute = endTime.minute
        guard let start = calendar.date(from: startComponents),
              let end = calendar.date(from: endComponents),
              end > start else { return nil }
        return DateInterval(start: start, end: end)
    }

    private var isValid: Bool { interval != nil }
}
