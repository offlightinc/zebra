import SwiftUI

/// Shared priority indicator. Urgent gets a warning-triangle SF Symbol,
/// the other three levels reuse `PriorityBars`. `nil` renders the three-dot
/// "no priority" glyph.
struct TaskPriorityIcon: View {
    let priority: BrainPriority?

    var body: some View {
        if let p = priority {
            if p == .urgent {
                ZStack {
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(BVColor.priorityUrgent)
                    Image(systemName: "exclamationmark")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundColor(.white)
                        .offset(y: -1)
                }
                .frame(width: 12, height: 12)
            } else {
                PriorityBars(level: Self.level(p), color: BVColor.fgMute)
            }
        } else {
            TaskNoPriorityGlyph()
        }
    }

    static func level(_ p: BrainPriority) -> Int {
        switch p { case .urgent: return 3; case .high: return 3; case .medium: return 2; case .low: return 1 }
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
