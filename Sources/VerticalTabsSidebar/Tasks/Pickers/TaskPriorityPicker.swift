import SwiftUI

struct TaskPriorityPicker: View {
    let current: BrainPriority?
    let onSelect: (BrainPriority?) -> Void

    /// Display order. nil = "No priority" (key 0), then urgent/high/normal/low (1–4).
    private static let ordered: [BrainPriority] = [.urgent, .high, .normal, .low]

    var body: some View {
        VStack(spacing: 0) {
            Button(action: { onSelect(nil) }) {
                HStack(spacing: 8) {
                    noneGlyph
                    Text(String(localized: "task.priority.none", defaultValue: "No priority"))
                        .font(.system(size: 12))
                        .foregroundColor(BVColor.fg)
                    Spacer()
                    if current == nil {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(BVColor.fgMute)
                    }
                    Text("0")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(BVColor.fgFaint)
                        .frame(minWidth: 14, alignment: .trailing)
                }
                .padding(.horizontal, 10)
                .frame(height: 26)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(KeyEquivalent("0"), modifiers: [])

            ForEach(Array(Self.ordered.enumerated()), id: \.element) { idx, p in
                Button(action: { onSelect(p) }) {
                    HStack(spacing: 8) {
                        priorityIcon(p).frame(width: 14, height: 14)
                        Text(TaskListViewModel.priorityLabel(p))
                            .font(.system(size: 12))
                            .foregroundColor(BVColor.fg)
                        Spacer()
                        if current == p {
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

    private var noneGlyph: some View {
        TaskNoPriorityGlyph()
    }

    private func priorityIcon(_ p: BrainPriority) -> some View {
        TaskPriorityIcon(priority: p)
    }
}
