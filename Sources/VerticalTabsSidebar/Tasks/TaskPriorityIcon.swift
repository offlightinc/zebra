import SwiftUI

/// Shared priority indicator. Urgent gets a warning-triangle SF Symbol,
/// the other three levels reuse `PriorityBars`. `nil` renders the three-dot
/// "no priority" glyph.
struct TaskPriorityIcon: View {
    let priority: BrainPriority?

    var body: some View {
        if let p = priority {
            if p == .urgent {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(BVColor.priorityUrgent)
            } else {
                PriorityBars(level: Self.level(p), color: Self.color(p))
            }
        } else {
            TaskNoPriorityGlyph()
        }
    }

    static func level(_ p: BrainPriority) -> Int {
        switch p { case .urgent: return 3; case .high: return 3; case .normal: return 2; case .low: return 1 }
    }

    static func color(_ p: BrainPriority) -> Color {
        switch p {
        case .urgent: return BVColor.priorityUrgent
        case .high:   return BVColor.priorityHigh
        case .normal: return BVColor.priorityNormal
        case .low:    return BVColor.priorityLow
        }
    }
}

struct TaskNoPriorityGlyph: View {
    var body: some View {
        HStack(spacing: 1.6) {
            Circle().fill(BVColor.fgFaint).frame(width: 2, height: 2)
            Circle().fill(BVColor.fgFaint).frame(width: 2, height: 2)
            Circle().fill(BVColor.fgFaint).frame(width: 2, height: 2)
        }
        .frame(width: 14, height: 14)
    }
}
