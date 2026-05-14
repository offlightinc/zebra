import SwiftUI

struct TaskGroupByPicker: View {
    let current: TaskGroupBy
    let onSelect: (TaskGroupBy) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(TaskGroupBy.allCases.enumerated()), id: \.element) { idx, opt in
                Button(action: { onSelect(opt) }) {
                    HStack(spacing: 8) {
                        Text(opt.label)
                            .font(.system(size: 12))
                            .foregroundColor(BVColor.fg)
                        Spacer()
                        if current == opt {
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
                .keyboardShortcut(KeyEquivalent(Character("\(idx + 1)")), modifiers: [])
            }
        }
        .padding(.vertical, 4)
        .frame(width: 200)
        .background(BVColor.bgElev)
    }
}
