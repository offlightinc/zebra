import SwiftUI

/// Inline slash-skills picker that the pill embeds when the user is mid-`/`.
/// Receives a flat list of skills, the current slash filter (used in the
/// empty state copy), and a selectedIndex binding so keyboard navigation
/// from the pill's NSEvent monitor reflects here without duplicating state.
///
/// Pulled out of `MarkdownChatPill.swift` so the per-row layout, glyph
/// pool, FNV hash, scroll-into-view bookkeeping, and hover plumbing don't
/// share a 1000-line file with the rest of the pill's state machine.
struct MarkdownChatPillSkillsPicker: View {
    let skills: [BrainSkillsManifest.Skill]
    let slashFilter: String
    @Binding var selectedIndex: Int
    let onPick: (BrainSkillsManifest.Skill) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: ✨ BRAIN SKILLS · N         ↑↓ ↵
            // `sparkles` is the closest SF Symbol to the mockup's `spark`
            // icon (a big + small star pair). The single-star `sparkle`
            // doesn't capture the two-star silhouette.
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11))
                    .foregroundColor(MarkdownPillPalette.accent)
                Text(String(localized: "markdownChat.pill.skills.header",
                            defaultValue: "BRAIN SKILLS"))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(MarkdownPillPalette.textDim)
                    .kerning(1.0)
                Text("· \(skills.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(MarkdownPillPalette.textDim)
                Spacer(minLength: 4)
                MarkdownPillKbdLabel("↑↓")
                MarkdownPillKbdLabel("↵")
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 4)

            if skills.isEmpty {
                HStack(spacing: 4) {
                    Text(String(localized: "markdownChat.pill.skills.empty",
                                defaultValue: "No skills match"))
                    Text("/\(slashFilter)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(MarkdownPillPalette.textMuted)
                }
                .font(.system(size: 12))
                .foregroundColor(MarkdownPillPalette.textDim)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            } else {
                // ScrollViewReader so ↑/↓ keyboard navigation keeps the
                // highlighted row visible. Each row carries `.id(index)`,
                // and we scroll-to the selected index on every change.
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(skills.enumerated()), id: \.element.id) { index, skill in
                                row(skill: skill, index: index, isSelected: index == selectedIndex)
                                    .id(index)
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                    .onChange(of: selectedIndex) { _, newIndex in
                        // No `anchor:` → ScrollViewProxy scrolls the
                        // minimum amount needed to bring the target into
                        // view. With `.center`, every keystroke would jerk
                        // an already-visible row toward the middle.
                        withAnimation(.linear(duration: 0.08)) {
                            proxy.scrollTo(newIndex)
                        }
                    }
                }
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.03))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(MarkdownPillPalette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Row + helpers

    private func row(skill: BrainSkillsManifest.Skill, index: Int, isSelected: Bool) -> some View {
        // mockup's `SKILLS` data ships per-row scope; the project rows use a
        // warm yellow (#e8b75c) for both the glyph tile and the badge. gbrain
        // doesn't carry a scope so we surface every row in the yellow tone —
        // matches the visual reference the user is comparing against
        // (mockup screenshot of /plan-pr, /ship-checklist, /sync-linear).
        let tint = MarkdownPillPalette.selectionTint
        return Button {
            onPick(skill)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Text(Self.glyph(for: skill.name))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(tint)
                    .frame(width: 22, height: 22)
                    .background(tint.opacity(0.13))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("/\(skill.name)")
                            .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                            .foregroundColor(MarkdownPillPalette.text)
                        Text(String(localized: "markdownChat.pill.skills.badge",
                                    defaultValue: "brain"))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(tint)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(tint.opacity(0.13))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    if !skill.description.isEmpty {
                        Text(skill.description)
                            .font(.system(size: 11.5))
                            .foregroundColor(MarkdownPillPalette.textMuted)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? tint.opacity(0.10) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Mouse hover should mirror keyboard navigation: whichever row the
        // pointer is over becomes the highlighted one, so the visual
        // selection stays in sync regardless of input device.
        .onHover { inside in
            if inside { selectedIndex = index }
        }
    }

    // MARK: - Glyph hash

    /// Glyph pool from mockup `md-app.jsx::SKILLS`. gbrain's manifest doesn't
    /// ship per-skill glyphs, so we deterministically hash the skill name to
    /// a glyph for stable visuals across launches.
    private static let glyphs: [String] = ["✦", "◐", "◇", "▲", "★", "✓", "↗"]

    private static func glyph(for skillName: String) -> String {
        // Swift's `String.hashValue` is randomized per process launch, so the
        // same skill would draw a different glyph after every restart. Use a
        // hand-rolled FNV-1a so the mapping stays stable for the lifetime of
        // the install. UInt arithmetic also dodges the `Int.min.abs` trap
        // that the previous `abs(hashValue)` form was technically vulnerable
        // to.
        let fnvOffset: UInt64 = 0xcbf29ce484222325
        let fnvPrime: UInt64 = 0x100000001b3
        var hash = fnvOffset
        for byte in skillName.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* fnvPrime
        }
        let bucket = Int(hash % UInt64(glyphs.count))
        return glyphs[bucket]
    }
}
