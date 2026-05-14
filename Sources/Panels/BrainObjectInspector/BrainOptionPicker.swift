import SwiftUI

/// Generic option picker used inside `.panelPopover` content. Renders an
/// option list with a leading glyph, label, current ✓, and keyboard
/// shortcut (1–N). Optionally prepends a "none" row with key 0.
///
/// No search box — the caller is expected to use this only for short option
/// sets (≤ 9, enforced by precondition) where keyboard 1–N is faster than
/// typing. For variable-length lists (people, tags), use the dedicated
/// `OwnerPickerView` etc.
struct BrainOptionPicker<Item: Hashable, Glyph: View>: View {
    let items: [Item]
    let current: Item?
    let label: (Item) -> String
    @ViewBuilder let glyph: (Item) -> Glyph
    /// Called with the selected item, or nil when the "none" row is chosen.
    let onSelect: (Item?) -> Void

    /// Optional leading row representing "no value" — gets keyboard "0".
    /// The glyph is `AnyView` because there is only one caller (priority);
    /// promoting it to a second generic parameter would noise up every call
    /// site without measurable benefit.
    var noneOption: NoneOption? = nil

    var width: CGFloat = 220

    struct NoneOption {
        let label: String
        let glyph: AnyView
    }

    var body: some View {
        // `Character("\(idx+1)")` traps for multi-digit strings, so cap the
        // shortcut range. Callers in this codebase all use ≤6 options.
        let _ = precondition(items.count <= 9, "BrainOptionPicker supports up to 9 items (keyboard shortcuts 1–9). Got \(items.count).")

        VStack(spacing: 0) {
            if let none = noneOption {
                row(
                    glyph: none.glyph,
                    label: none.label,
                    isCurrent: current == nil,
                    keyLabel: "0",
                    keyShortcut: KeyEquivalent("0"),
                    action: { onSelect(nil) }
                )
            }
            ForEach(Array(items.enumerated()), id: \.element) { idx, item in
                let keyChar = Character("\(idx + 1)")
                row(
                    glyph: AnyView(glyph(item)),
                    label: label(item),
                    isCurrent: current == item,
                    keyLabel: "\(idx + 1)",
                    keyShortcut: KeyEquivalent(keyChar),
                    action: { onSelect(item) }
                )
            }
        }
        .padding(.vertical, 4)
        .frame(width: width)
        .background(BVColor.bgElev)
    }

    private func row(
        glyph: AnyView,
        label: String,
        isCurrent: Bool,
        keyLabel: String,
        keyShortcut: KeyEquivalent,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                glyph
                    .frame(width: 14, height: 14)
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(BVColor.fg)
                Spacer()
                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(BVColor.fgMute)
                }
                Text(keyLabel)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(BVColor.fgFaint)
                    .frame(minWidth: 14, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(keyShortcut, modifiers: [])
        .background(EditablePickerRowHoverBackground())
    }
}
