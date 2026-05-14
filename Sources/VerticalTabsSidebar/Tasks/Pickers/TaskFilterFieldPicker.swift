import SwiftUI

/// Step 1 of the filter flow: pick a field. Existing fields show "Edit" hint.
struct TaskFilterFieldPicker: View {
    let existingFields: Set<TaskFilterField>
    let onSelect: (TaskFilterField) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text(String(localized: "task.filter.addHeader", defaultValue: "Add filter"))
                .font(.system(size: 10.5))
                .fontWeight(.semibold)
                .foregroundColor(BVColor.fgFaint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 4)
            ForEach(TaskFilterField.allCases, id: \.self) { field in
                Button(action: { onSelect(field) }) {
                    HStack(spacing: 8) {
                        Text(field.label)
                            .font(.system(size: 12))
                            .foregroundColor(BVColor.fg)
                        Spacer()
                        if existingFields.contains(field) {
                            Text(String(localized: "task.filter.edit", defaultValue: "Edit"))
                                .font(.system(size: 10.5))
                                .foregroundColor(BVColor.fgMute)
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 4)
        .frame(width: 200)
        .background(BVColor.bgElev)
    }
}
