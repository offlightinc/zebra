import SwiftUI

/// Inline-editable status pill for a task. Pill chrome mirrors
/// `StatusPillView` (the read-only counterpart at
/// `BrainObjectInspectorAtoms.swift`) so the inspector layout is unchanged;
/// only the trigger gains a popover.
struct EditableTaskStatusPill: View {
    let value: BrainTaskStatus?
    let onChange: (BrainTaskStatus?) -> Void

    @State private var isPresented = false

    var body: some View {
        Button(action: { isPresented = true }) {
            HStack(spacing: 5) {
                if let value {
                    StatusGlyph(status: value).frame(width: 12, height: 12)
                    Text(value.localizedLabel)
                        .font(.system(size: 11.5))
                        .foregroundColor(BVColor.fg)
                } else {
                    Circle()
                        .strokeBorder(BVColor.fgFaint, style: StrokeStyle(lineWidth: 1, dash: [2, 1.4]))
                        .frame(width: 12, height: 12)
                    Text(String(localized: "brain.editable.setStatus", defaultValue: "Set status..."))
                        .font(.system(size: 11.5).italic())
                        .foregroundColor(BVColor.fgFaint)
                }
            }
            .inspectorPillChrome()
        }
        .buttonStyle(.plain)
        .panelPopover(isPresented: $isPresented) {
            OptionPicker(
                current: value,
                ordered: BrainTaskStatus.primaryCases,
                title: String(localized: "brain.status.picker.title", defaultValue: "Change status"),
                label: { $0.localizedLabel },
                glyph: { StatusGlyph(status: $0) },
                onSelect: { selected in
                    if let selected, selected != value {
                        onChange(selected)
                    }
                    isPresented = false
                }
            )
        }
        .accessibilityLabel(Text(value.map { $0.localizedLabel } ?? String(localized: "brain.editable.setStatus", defaultValue: "Set status...")))
    }
}

/// Inline-editable priority pill for a task. Pill chrome mirrors
/// `PriorityPillView`; popover prepends a "No priority" row (key 0)
/// followed by urgent/high/normal/low (keys 1–4).
struct EditableTaskPriorityPill: View {
    let value: BrainPriority?
    let onChange: (BrainPriority?) -> Void

    @State private var isPresented = false

    var body: some View {
        Button(action: { isPresented = true }) {
            HStack(spacing: 5) {
                if let value {
                    TaskPriorityIcon(priority: value).frame(width: 12, height: 12)
                    Text(value.localizedLabel)
                        .font(.system(size: 11.5))
                        .foregroundColor(BVColor.fg)
                } else {
                    TaskNoPriorityGlyph().frame(width: 12, height: 12)
                    Text(String(localized: "brain.editable.setPriority", defaultValue: "Set priority..."))
                        .font(.system(size: 11.5).italic())
                        .foregroundColor(BVColor.fgFaint)
                }
            }
            .inspectorPillChrome()
        }
        .buttonStyle(.plain)
        .panelPopover(isPresented: $isPresented) {
            OptionPicker(
                current: value,
                ordered: [.urgent, .high, .medium, .low],
                title: String(localized: "task.picker.priority.title", defaultValue: "Change priority"),
                label: { $0.localizedLabel },
                glyph: { TaskPriorityIcon(priority: $0) },
                noneRow: .init(
                    label: String(localized: "task.priority.none", defaultValue: "No priority"),
                    glyph: AnyView(TaskNoPriorityGlyph())
                ),
                onSelect: { selected in
                    if selected != value {
                        onChange(selected)
                    }
                    isPresented = false
                }
            )
        }
        .accessibilityLabel(Text(value.map { $0.localizedLabel } ?? String(localized: "brain.editable.setPriority", defaultValue: "Set priority...")))
    }
}
