import SwiftUI

/// Compact month grid for date picker popovers.
/// Replaces system graphical date pickers where we need cmux/zebra styling.
struct CompactMonthCalendar: View {
    @Binding var date: Date

    @State private var displayMonth: Date

    init(date: Binding<Date>) {
        self._date = date
        self._displayMonth = State(initialValue: date.wrappedValue)
    }

    private let cellHeight: CGFloat = 22
    private let cellDot: CGFloat = 20
    private let horizontalPad: CGFloat = 14
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 1
        return c
    }()
    private let weekdaySymbols = ["일", "월", "화", "수", "목", "금", "토"]
    private let sundayColor = Color(.sRGB, red: 0.94, green: 0.35, blue: 0.35, opacity: 0.7)

    var body: some View {
        VStack(spacing: 0) {
            header
            weekStrip
            grid
        }
        .frame(width: 240)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text(monthLabel)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(BVColor.fg)
                .tracking(-0.1)
            Spacer(minLength: 4)
            HStack(spacing: 10) {
                chevronButton(systemName: "chevron.left", action: prevMonth)
                Button(action: jumpToToday) {
                    Circle()
                        .fill(BVColor.fgMute)
                        .frame(width: 5, height: 5)
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                chevronButton(systemName: "chevron.right", action: nextMonth)
            }
        }
        .padding(.horizontal, horizontalPad)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private func chevronButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(BVColor.fgMute)
                .padding(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var weekStrip: some View {
        HStack(spacing: 0) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { index, weekday in
                Text(weekday)
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.4)
                    .foregroundColor(index == 0 ? sundayColor : BVColor.fgMute)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
        }
        .padding(.horizontal, horizontalPad)
        .padding(.bottom, 2)
    }

    private var grid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7),
            spacing: 0
        ) {
            ForEach(monthCells, id: \.id) { cell in
                cellView(for: cell)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private func cellView(for cell: DayCell) -> some View {
        let isToday = calendar.isDateInToday(cell.date)
        let isSelected = calendar.isDate(cell.date, inSameDayAs: date)

        return ZStack {
            if isSelected {
                Circle()
                    .fill(BVColor.accent)
                    .frame(width: cellDot, height: cellDot)
            } else if isToday {
                Circle()
                    .strokeBorder(BVColor.accent, lineWidth: 1.5)
                    .frame(width: cellDot, height: cellDot)
            }
            Text("\(cell.day)")
                .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                .foregroundColor(textColor(for: cell, isSelected: isSelected))
                .monospacedDigit()
        }
        .frame(height: cellHeight)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            date = cell.date
            if !cell.inDisplayedMonth {
                displayMonth = cell.date
            }
        }
        .accessibilityLabel(Text(accessibilityLabel(for: cell, isSelected: isSelected, isToday: isToday)))
    }

    private func textColor(for cell: DayCell, isSelected: Bool) -> Color {
        if isSelected { return .white }
        if !cell.inDisplayedMonth { return BVColor.fgGhost }
        return BVColor.fg
    }

    private func accessibilityLabel(for cell: DayCell, isSelected: Bool, isToday: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateStyle = .medium
        var label = formatter.string(from: cell.date)
        if isToday { label += ", 오늘" }
        if isSelected { label += ", 선택됨" }
        return label
    }

    private struct DayCell: Identifiable {
        let id: TimeInterval
        let date: Date
        let day: Int
        let inDisplayedMonth: Bool
    }

    private var monthLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월"
        return formatter.string(from: displayMonth)
    }

    private var monthCells: [DayCell] {
        let comps = calendar.dateComponents([.year, .month], from: displayMonth)
        guard let firstOfMonth = calendar.date(from: comps),
              let daysInMonth = calendar.range(of: .day, in: .month, for: firstOfMonth)?.count
        else { return [] }

        let firstWeekdayIndex = (calendar.component(.weekday, from: firstOfMonth) - calendar.firstWeekday + 7) % 7
        var cells: [DayCell] = []

        if firstWeekdayIndex > 0,
           let prevMonth = calendar.date(byAdding: .day, value: -1, to: firstOfMonth) {
            let daysInPrev = calendar.range(of: .day, in: .month, for: prevMonth)?.count ?? 0
            for offset in stride(from: firstWeekdayIndex - 1, through: 0, by: -1) {
                let day = daysInPrev - offset
                let distance = -firstWeekdayIndex + (firstWeekdayIndex - 1 - offset)
                if let d = calendar.date(byAdding: .day, value: distance, to: firstOfMonth) {
                    cells.append(DayCell(
                        id: d.timeIntervalSinceReferenceDate,
                        date: d,
                        day: day,
                        inDisplayedMonth: false
                    ))
                }
            }
        }

        for index in 0..<daysInMonth {
            if let d = calendar.date(byAdding: .day, value: index, to: firstOfMonth) {
                cells.append(DayCell(
                    id: d.timeIntervalSinceReferenceDate,
                    date: d,
                    day: index + 1,
                    inDisplayedMonth: true
                ))
            }
        }

        var next = 0
        while cells.count < 42 {
            if let d = calendar.date(byAdding: .day, value: daysInMonth + next, to: firstOfMonth) {
                cells.append(DayCell(
                    id: d.timeIntervalSinceReferenceDate,
                    date: d,
                    day: calendar.component(.day, from: d),
                    inDisplayedMonth: false
                ))
            }
            next += 1
        }

        return cells
    }

    private func prevMonth() {
        if let d = calendar.date(byAdding: .month, value: -1, to: displayMonth) {
            displayMonth = d
        }
    }

    private func nextMonth() {
        if let d = calendar.date(byAdding: .month, value: 1, to: displayMonth) {
            displayMonth = d
        }
    }

    private func jumpToToday() {
        displayMonth = Date()
    }
}
