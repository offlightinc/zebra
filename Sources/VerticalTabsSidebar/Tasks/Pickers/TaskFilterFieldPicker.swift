import SwiftUI

/// Step 1 of the filter flow: pick a field. Existing fields show "Edit" hint.
struct TaskFilterFieldPicker: View {
    let existingFields: Set<TaskFilterField>
    let onSelect: (TaskFilterField) -> Void

    var body: some View {
        TaskPickerContainer(
            title: String(localized: "task.filter.addHeader", defaultValue: "Add filter"),
            width: 220
        ) {
            ForEach(TaskFilterField.allCases, id: \.self) { field in
                let existing = existingFields.contains(field)
                TaskPickerRow(
                    glyph: { EmptyView() },
                    label: field.label,
                    isCurrent: existing,
                    // HTML prototype: 기존 필드 옆에 "편집" 텍스트 힌트. 새 필드와
                    // 클릭 동작은 같지만(둘 다 step 2로 진행) 사용자가 기존 필터를
                    // 수정하러 가는 거라는 신호.
                    keyLabel: existing
                        ? String(localized: "task.filter.edit", defaultValue: "편집")
                        : nil,
                    action: { onSelect(field) }
                )
            }
        }
    }
}
