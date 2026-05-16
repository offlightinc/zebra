import SwiftUI

/// 사이드바 Task / Goal row 의 due/target_date 시각 표현. 두 도메인 모두
/// "객체가 끝나야 할 날짜" 라는 같은 추상을 공유하므로 같은 label 어휘와
/// 시각을 쓴다. plain text (배경 없음) + 색 강조 (urgent vs faint) + weight
/// 강조 (overdue 면 semibold).
///
/// Label 형식:
///   - abs(days) < 7 → "Nd" / "-Nd"   (3d / -2d)
///   - abs(days) ≥ 7 → "Nw" / "-Nw"   (3w / -1w)
///   - 색: days ≤ 1 → urgent (red), else faint (gray)
///   - weight: days < 0 → semibold (overdue), else regular
enum SidebarDueLabel {
    struct Descriptor: Equatable {
        let label: String
        let color: Color
        let weight: Font.Weight
    }

    static func descriptor(for date: Date?, now: Date = Date()) -> Descriptor? {
        guard let date else { return nil }
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let target = cal.startOfDay(for: date)
        let days = cal.dateComponents([.day], from: today, to: target).day ?? 0

        let label: String = {
            if abs(days) >= 7 { return "\(days / 7)w" }
            return "\(days)d"
        }()
        let weight: Font.Weight = days < 0 ? .semibold : .regular
        let color: Color = days <= 1 ? BVColor.priorityUrgent : BVColor.fgFaint
        return Descriptor(label: label, color: color, weight: weight)
    }
}

/// 사이드바 row 안의 due label 텍스트. `SidebarDueLabel.descriptor` 결과를
/// 받아 일관된 폰트/색/weight 로 렌더.
struct SidebarDueLabelText: View {
    let descriptor: SidebarDueLabel.Descriptor

    var body: some View {
        Text(descriptor.label)
            .font(.system(size: 11, weight: descriptor.weight).monospacedDigit())
            .foregroundColor(descriptor.color)
    }
}
