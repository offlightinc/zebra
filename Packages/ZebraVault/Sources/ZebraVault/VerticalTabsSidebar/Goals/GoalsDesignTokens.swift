import SwiftUI

enum GoalsDesignTokens {
    static let columnWidth: CGFloat = 240
    // Row 는 dynamic height 사용 (rowVerticalPadding × 2 + font line-height).
    // Tasks 와 동일 (TaskListRow: .padding(.vertical, 5) + font 13pt).
    static let rowFontSize: CGFloat = 13
    static let rowVerticalPadding: CGFloat = 5
    static let rowHorizontalPadding: CGFloat = 12

    static let groupHeaderFontSize: CGFloat = 11
    static let groupHeaderHorizontalPadding: CGFloat = 12
    static let groupHeaderTopPadding: CGFloat = 14
    static let groupHeaderBottomPadding: CGFloat = 4
    static let groupHeaderCountSpacing: CGFloat = 6

    // Picker font/padding 은 Tasks toolbar (TaskListToolbar) 와 통일 — 모드
    // 전환 시 두 번째 줄 외곽 height 가 점프하지 않도록 동일 font+padding 으로
    // dynamic height 가 자연히 일치한다.
    static let pickerFontSize: CGFloat = 11.5
    static let pickerOuterHorizontalPadding: CGFloat = 10
    static let pickerVerticalPadding: CGFloat = 6
    static let pickerSegmentHorizontalPadding: CGFloat = 7
    static let pickerSegmentVerticalPadding: CGFloat = 4
    static let pickerCornerRadius: CGFloat = 7
    static let pickerSegmentCornerRadius: CGFloat = 6

    // 우측 meta (status row 의 N/M, cadence row 의 due) 는 Task 의 due 와
    // 일관 — font 11pt + plain text. 색은 Task SidebarDueLabel 의 fgFaint 와
    // 동일.
    static let metaFontSize: CGFloat = 11

    static let outlineChevronColumnWidth: CGFloat = 16
    static let outlineIndentPerLevel: CGFloat = 16

    static let selectionAlpha: Double = 0.18

    static let strikethroughLineWidth: CGFloat = 1
}
