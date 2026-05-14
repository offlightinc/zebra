import SwiftUI

struct TaskStatusPicker: View {
    let current: BrainTaskStatus?
    let onSelect: (BrainTaskStatus) -> Void

    private static let ordered: [BrainTaskStatus] = [
        .todo, .doing, .blocked, .waiting, .completed, .canceled
    ]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(Self.ordered.enumerated()), id: \.element) { idx, status in
                Button(action: { onSelect(status) }) {
                    HStack(spacing: 8) {
                        StatusGlyph(status: status).frame(width: 14, height: 14)
                        Text(TaskListViewModel.statusLabel(status))
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
                .keyboardShortcut(KeyEquivalent(Character("\(idx + 1)")), modifiers: [])
            }
        }
        .padding(.vertical, 4)
        .frame(width: 220)
        .background(BVColor.bgElev)
    }
}
