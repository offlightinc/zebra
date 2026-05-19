import AppKit
import SwiftUI

// Floating chat pill overlay for MarkdownPanelView.
//
// Three visual states wired through `isExpanded` × `activeAgent`:
//   - idle (no companion pane, collapsed): "Ask about this doc"
//   - companion (agent pane live, collapsed): "session · <agent> · New session…"
//   - expanded: textfield + chips + agent dropdown + slash skills picker
// Submit / agent change routing is owned by the parent
// `MarkdownPanelView` via the `onSubmit` closure; the pill stays
// presentational. See `MarkdownChatPillCommand` for the shell-side
// invocation contract and `MarkdownChatPillSkillsPicker` for the
// slash-menu UI.

private extension MarkdownPillAgent {
    var shortcutHint: String {
        switch self {
        case .codex: return "⌥1"
        case .claude: return "⌥2"
        case .gemini: return "⌥3"
        }
    }

    // Mockup-faithful (placeholder marks, not real brands) — md-chat.jsx::AgentDot
    var glyph: String {
        switch self {
        case .codex: return "◇"
        case .claude: return "✳"
        case .gemini: return "✦"
        }
    }

    var glyphBg: Color {
        switch self {
        case .codex: return Color(red: 15.0 / 255, green: 15.0 / 255, blue: 15.0 / 255)
        case .claude: return Color(red: 201.0 / 255, green: 100.0 / 255, blue: 66.0 / 255)
        case .gemini: return Color(red: 42.0 / 255, green: 77.0 / 255, blue: 173.0 / 255)
        }
    }

    var glyphColor: Color {
        switch self {
        case .codex: return Color(red: 230.0 / 255, green: 228.0 / 255, blue: 221.0 / 255)
        case .claude, .gemini: return .white
        }
    }
}

struct MarkdownPillAgentDot: View {
    let agent: MarkdownPillAgent
    var size: CGFloat = 14

    var body: some View {
        Text(agent.glyph)
            .font(.system(size: size * 0.7, weight: .semibold, design: .monospaced))
            .foregroundColor(agent.glyphColor)
            .frame(width: size, height: size)
            .background(agent.glyphBg)
            .clipShape(RoundedRectangle(cornerRadius: size / 4))
    }
}

// Palette pulled from mockup MD_PALETTE (md-chat.jsx). Hex values are
// matched exactly so the pill renders the same warm cream-on-dark tone
// as the design prototype rather than a colder pure-white-on-dark.
//
// Module-internal (not file-private) so the split-out picker and selection
// helpers in sibling files can share the exact same palette without
// duplicating hex constants.
enum MarkdownPillPalette {
    static let pillBg = Color(red: 20.0 / 255, green: 21.0 / 255, blue: 24.0 / 255).opacity(0.92)
    static let pillBgExpanded = Color(red: 20.0 / 255, green: 21.0 / 255, blue: 24.0 / 255).opacity(0.96)
    static let text = Color(red: 230.0 / 255, green: 228.0 / 255, blue: 221.0 / 255)
    static let textMuted = Color(red: 154.0 / 255, green: 149.0 / 255, blue: 138.0 / 255)
    static let textDim = Color(red: 108.0 / 255, green: 105.0 / 255, blue: 96.0 / 255)
    static let border = Color.white.opacity(0.07)
    static let borderStrong = Color.white.opacity(0.12)
    static let accent = Color(red: 123.0 / 255, green: 227.0 / 255, blue: 196.0 / 255)
    // Pre-blended dim teal — equivalent to rgba(123,227,196,0.45) on dark pill bg.
    // mockup's 0.25 reads too washed-out once layered on the semi-opaque pill;
    // bumping saturation keeps the button visible while still clearly disabled.
    static let sendDim = Color(red: 76.0 / 255, green: 130.0 / 255, blue: 115.0 / 255)
    static let buttonSurface = Color.white.opacity(0.04)
    /// Warm yellow (mockup `::selection` + project-scope chip) used for
    /// selection chip + slash skill picker.
    static let selectionTint = Color(red: 232.0 / 255, green: 183.0 / 255, blue: 92.0 / 255)
}

public struct MarkdownChatPill: View {
    private static let maxWidth: CGFloat = 720
    private static let collapsedHeight: CGFloat = 46
    private static let collapsedContentHeight: CGFloat = 30
    private static let expandedHeight: CGFloat = 156
    private static let expandedChipMaxWidth: CGFloat = 320
    private static let motion = Animation.timingCurve(0.4, 0.0, 0.2, 1.0, duration: 0.30)

    let displayTitle: String
    /// Non-nil when this markdown already has a companion pane for agent
    /// tabs. Submit still creates a fresh terminal tab; this only changes
    /// the collapsed affordance.
    let activeAgent: MarkdownPillAgent?
    /// Parent handles the actual split/tab creation and terminal input.
    /// The pill just emits the user's intent.
    let onSubmit: (_ text: String, _ agent: MarkdownPillAgent) -> Void

    public init(
        isExpanded: Binding<Bool>,
        displayTitle: String,
        activeAgent: MarkdownPillAgent?,
        onSubmit: @escaping (_ text: String, _ agent: MarkdownPillAgent) -> Void
    ) {
        self._isExpanded = isExpanded
        self.displayTitle = displayTitle
        self.activeAgent = activeAgent
        self.onSubmit = onSubmit
    }

    @Binding private var isExpanded: Bool
    @State private var text: String = ""
    @State private var agent: MarkdownPillAgent = .codex
    @State private var agentMenuOpen: Bool = false
    /// Cached gbrain skill list, loaded lazily on first slash. nil means
    /// "didn't try yet" — empty array means we tried and gbrain isn't
    /// installed (picker stays hidden).
    @State private var skillsCache: [BrainSkillsManifest.Skill]?
    /// Currently highlighted row in the slash picker for ↑↓ keyboard
    /// navigation. Reset to 0 whenever the filter changes so the top match
    /// is always the default selection.
    @State private var skillsSelectedIndex: Int = 0
    /// First-responder state for the NSTextView wrapper. Mirrored from the
    /// view's `becomeFirstResponder` / `resignFirstResponder` overrides so
    /// the pill's expand/collapse logic can read and drive focus from
    /// SwiftUI-land. Not a `@FocusState` because that only binds to SwiftUI
    /// focusable views, and our input is an NSView underneath.
    @State private var textFieldFocused: Bool = false

    /// True while the user is mid-slash — input begins with `/` and has no
    /// whitespace yet, so we can offer skill completions. Once they type a
    /// space the slash command is "committed" and the picker hides.
    private var isSlashMode: Bool {
        guard text.hasPrefix("/") else { return false }
        return !text.contains(" ")
    }

    /// `/foo` → `foo`. Empty filter (bare `/`) shows the full list.
    private var slashFilter: String {
        guard text.hasPrefix("/") else { return "" }
        return String(text.dropFirst())
    }

    /// Skills matching the current slash filter, case-insensitive, on name
    /// or description. Returns nil when manifest hasn't been loaded yet or
    /// gbrain isn't installed.
    private var matchingSkills: [BrainSkillsManifest.Skill]? {
        guard let skills = skillsCache else { return nil }
        let q = slashFilter.lowercased()
        guard !q.isEmpty else { return skills }
        return skills.filter { skill in
            skill.name.lowercased().contains(q) || skill.description.lowercased().contains(q)
        }
    }

    /// Insert the picked skill into the textfield as `/skill-name ` so the
    /// user can keep typing arguments. The trailing space also commits the
    /// slash command (isSlashMode goes false) which auto-closes the picker.
    private func pickSkill(_ skill: BrainSkillsManifest.Skill) {
        text = "/\(skill.name) "
        DispatchQueue.main.async { textFieldFocused = true }
    }
    private var contextChipTitle: String {
        if !isExpanded || displayTitle.isEmpty {
            return String(localized: "markdownChat.pill.chip.thisDoc", defaultValue: "this doc")
        }
        return displayTitle
    }
    private var placeholderText: String {
        String(localized: "markdownChat.pill.placeholder.doc", defaultValue: "Ask about this doc")
    }
    private var shellCornerRadius: CGFloat {
        isExpanded ? 18 : Self.collapsedHeight / 2
    }
    private var shellHeight: CGFloat {
        isExpanded ? Self.expandedHeight : Self.collapsedHeight
    }
    private var shellPadding: CGFloat {
        isExpanded ? 14 : 8
    }
    private var expandedOpacity: Double {
        isExpanded ? 1 : 0
    }
    private var collapsedOpacity: Double {
        isExpanded ? 0 : 1
    }
    private var collapsedPromptText: String {
        placeholderText
    }

    public var body: some View {
        VStack(spacing: 8) {
            if isExpanded, isSlashMode, let skills = matchingSkills {
                skillsPicker(skills)
                    .frame(maxWidth: Self.maxWidth)
            }

            pillShell
        }
        .frame(maxWidth: Self.maxWidth)
        // Lazy-load the gbrain manifest the first time the user types a
        // slash. Empty array is a valid result (gbrain not installed) — it
        // still satisfies "cached", so we won't keep retrying every
        // keystroke.
        .onChange(of: text) { _, newValue in
            if newValue.hasPrefix("/"), skillsCache == nil {
                skillsCache = BrainSkillsManifest.skills() ?? []
            }
            // Filter changed → reset selection to the top match.
            skillsSelectedIndex = 0
        }
        .onChange(of: isExpanded) { _, expanded in
            if expanded, let activeAgent {
                agent = activeAgent
            }
            if !expanded {
                textFieldFocused = false
                agentMenuOpen = false
            }
        }
        // Focus-loss fallback. Mostly redundant with the parent dismiss
        // overlay, but catches paths where focus leaves without a click in
        // our window — app switch (⌘⇥), another textfield grabbing
        // first-responder programmatically, etc.
        .onChange(of: textFieldFocused) { _, focused in
            guard isExpanded, !focused else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                guard isExpanded, !textFieldFocused, !agentMenuOpen else { return }
                collapse()
            }
        }
    }

    private var pillShell: some View {
        ZStack(alignment: .topLeading) {
            shellBackground

            VStack(alignment: .leading, spacing: isExpanded ? 8 : 0) {
                headerRow
                    .frame(height: Self.collapsedContentHeight, alignment: .center)

                inputArea
                    .frame(height: isExpanded ? 38 : 0, alignment: .topLeading)
                    .opacity(expandedOpacity)
                    .offset(y: isExpanded ? 0 : -4)
                    .clipped()
                    .allowsHitTesting(isExpanded)
                    .accessibilityHidden(!isExpanded)

                dividerSlot
                    .frame(height: isExpanded ? 5 : 0, alignment: .topLeading)
                    .opacity(expandedOpacity)
                    .clipped()

                footerRow
                    .frame(height: isExpanded ? Self.collapsedContentHeight : 0, alignment: .topLeading)
                    .opacity(expandedOpacity)
                    .offset(y: isExpanded ? 0 : -4)
                    .clipped()
                    .allowsHitTesting(isExpanded)
                    .accessibilityHidden(!isExpanded)
            }
            .padding(shellPadding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: shellHeight, alignment: .topLeading)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: shellCornerRadius, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: shellHeight, alignment: .topLeading)
        .contentShape(RoundedRectangle(cornerRadius: shellCornerRadius, style: .continuous))
        .animation(Self.motion, value: isExpanded)
        .onTapGesture {
            guard !isExpanded else { return }
            expandFromCollapsed()
        }
        // Key routing lives in `MarkdownChatPillTextView` (NSTextView
        // subclass) so AppKit handles every standard caret/edit gesture
        // natively — ⌘←/→, ⌥←/→, ⇧+selection, ⇧⏎ for newline, etc. — and
        // we only see the four callbacks (return / move-up / move-down /
        // cancel) we explicitly opt into. The previous outer
        // `.onKeyPress(...)` stack pre-empted the focused TextField's key
        // map on macOS, which is why arrows and ⇧⏎ stopped working.
    }

    private var shellBackground: some View {
        RoundedRectangle(cornerRadius: shellCornerRadius, style: .continuous)
            .fill(isExpanded ? MarkdownPillPalette.pillBgExpanded : MarkdownPillPalette.pillBg)
            .overlay(
                RoundedRectangle(cornerRadius: shellCornerRadius, style: .continuous)
                    .stroke(MarkdownPillPalette.borderStrong, lineWidth: 1)
            )
            .shadow(
                color: Color.black.opacity(0.45),
                radius: 18,
                x: 0,
                y: 18
            )
            .frame(maxWidth: .infinity)
            .frame(height: shellHeight)
    }

    private func skillsPicker(_ skills: [BrainSkillsManifest.Skill]) -> some View {
        MarkdownChatPillSkillsPicker(
            skills: skills,
            slashFilter: slashFilter,
            selectedIndex: $skillsSelectedIndex,
            onPick: pickSkill
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity)
        .transaction { tx in
            tx.animation = nil
        }
    }

    private func expandFromCollapsed() {
        guard !isExpanded else { return }
        if let activeAgent {
            agent = activeAgent
        }
        withAnimation(Self.motion) {
            isExpanded = true
        }
        DispatchQueue.main.async {
            // NSTextView wrapper hooks updateNSView off this binding to
            // call `makeFirstResponder` and place the caret at the end
            // of any preserved text, so we don't need a separate
            // caret-to-end pass here.
            textFieldFocused = true
        }
    }

    private func collapse() {
        textFieldFocused = false
        withAnimation(Self.motion) {
            isExpanded = false
        }
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSubmit(trimmed, agent)
        text = ""
        collapse()
        textFieldFocused = false
    }

    // MARK: - Key callbacks (routed up from MarkdownChatPillTextView)

    /// NSTextView wrapper calls this on bare ⏎. Slash-picker takes
    /// priority over submit; empty text is a no-op. The wrapper always
    /// consumes the keystroke either way, so this returns `Void`.
    private func handleReturn() {
        if isSlashMode, let skills = matchingSkills, !skills.isEmpty {
            let safeIndex = min(max(0, skillsSelectedIndex), skills.count - 1)
            pickSkill(skills[safeIndex])
            return
        }
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            submit()
        }
    }

    /// Slash picker ↑ navigation. Returns true to consume the keystroke,
    /// false to let NSTextView do native caret movement.
    private func handleMoveUp() -> Bool {
        guard isSlashMode, let skills = matchingSkills, !skills.isEmpty else { return false }
        skillsSelectedIndex = max(0, skillsSelectedIndex - 1)
        return true
    }

    private func handleMoveDown() -> Bool {
        guard isSlashMode, let skills = matchingSkills, !skills.isEmpty else { return false }
        skillsSelectedIndex = min(skills.count - 1, skillsSelectedIndex + 1)
        return true
    }

    /// Escape collapses the pill when empty; otherwise we let NSTextView
    /// do whatever its native cancel handler wants (no-op in practice).
    private func handleCancel() -> Bool {
        guard isExpanded, text.isEmpty else { return false }
        collapse()
        return true
    }

    // MARK: - Unified shell slots

    private var headerRow: some View {
        HStack(spacing: 10) {
            leadingChipSlot

            promptModeLabel
                .layoutPriority(0)

            collapsedHeaderControls
                .opacity(collapsedOpacity)
                .allowsHitTesting(!isExpanded)
                .accessibilityHidden(isExpanded)
        }
    }

    private var leadingChipSlot: some View {
        ZStack(alignment: .leading) {
            contextChip(label: contextChipTitle)
                .opacity(activeAgent == nil || isExpanded ? 1 : 0)

            if activeAgent != nil {
                sessionChip
                    .opacity(collapsedOpacity)
            }
        }
        .frame(minWidth: 58, alignment: .leading)
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(0)
    }

    private var sessionChip: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(MarkdownPillPalette.accent)
                .frame(width: 6, height: 6)
            Text(String(localized: "markdownChat.pill.session.label", defaultValue: "session"))
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(MarkdownPillPalette.text)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Text("·")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(MarkdownPillPalette.textMuted)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Text(activeAgent?.label ?? "")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(MarkdownPillPalette.textMuted)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(MarkdownPillPalette.accent.opacity(0.10))
        .overlay(Capsule().stroke(MarkdownPillPalette.accent.opacity(0.30), lineWidth: 1))
        .clipShape(Capsule())
        .fixedSize(horizontal: true, vertical: false)
    }

    private var promptModeLabel: some View {
        ZStack(alignment: .leading) {
            Text(collapsedPromptText)
                .font(.system(size: 13.5))
                .foregroundColor(MarkdownPillPalette.textDim)
                .lineLimit(1)
                .truncationMode(.tail)
                .opacity(collapsedOpacity)

            Text(String(localized: "markdownChat.pill.context.auto", defaultValue: "· auto"))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(MarkdownPillPalette.textDim)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .opacity(expandedOpacity)
        }
        .frame(minWidth: 58, maxWidth: .infinity, alignment: .leading)
        .clipped()
    }

    private var collapsedHeaderControls: some View {
        HStack(spacing: 6) {
            if activeAgent == nil {
                agentSelectorButton(compact: true)
            }
            sendButton(enabled: false)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var inputArea: some View {
        // NSTextView wrapper so the pill input gets the full Cocoa text
        // keymap — ⌘←/→, ⌥←/→, Home/End, ⇧+selection, ⇧⏎ for newline,
        // word-wise delete, undo, IME composition. SwiftUI TextField
        // (NSTextField underneath) did not give us these.
        ZStack(alignment: .topLeading) {
            MarkdownChatPillTextView(
                text: $text,
                isFocused: $textFieldFocused,
                font: NSFont.systemFont(ofSize: 14),
                textColor: NSColor(MarkdownPillPalette.text),
                caretColor: NSColor(MarkdownPillPalette.accent),
                onReturn: { handleReturn() },
                onMoveUp: { handleMoveUp() },
                onMoveDown: { handleMoveDown() },
                onCancel: { handleCancel() }
            )
            .frame(maxWidth: .infinity, minHeight: 38, maxHeight: 38, alignment: .topLeading)

            if text.isEmpty {
                Text(placeholderText)
                    .font(.system(size: 14))
                    .foregroundColor(MarkdownPillPalette.textDim)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var dividerSlot: some View {
        Rectangle()
            .fill(MarkdownPillPalette.border)
            .frame(height: 1)
            .padding(.top, 4)
    }

    private var footerRow: some View {
        HStack(spacing: 6) {
            skillsButton

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                MarkdownPillKbdLabel("↵")
                Text(String(localized: "markdownChat.pill.footer.run", defaultValue: " run · "))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(MarkdownPillPalette.textDim)
                MarkdownPillKbdLabel("⇧↵")
                Text(String(localized: "markdownChat.pill.footer.newline", defaultValue: " newline"))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(MarkdownPillPalette.textDim)
            }
            .padding(.trailing, 4)

            agentSelectorButton(compact: false)
            sendButton(enabled: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    // MARK: - Sub-components

    private func contextChip(label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.system(size: 11))
                .foregroundColor(MarkdownPillPalette.accent)
            Text(label)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundColor(MarkdownPillPalette.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .padding(.vertical, 4)
        .background(MarkdownPillPalette.accent.opacity(0.10))
        .overlay(
            Capsule().stroke(MarkdownPillPalette.accent.opacity(0.25), lineWidth: 1)
        )
        .clipShape(Capsule())
        .fixedSize(horizontal: false, vertical: true)
    }

    private func agentSelectorButton(compact: Bool) -> some View {
        // Rolled our own picker instead of SwiftUI `Menu` because on macOS
        // Menu's custom `label:` keeps collapsing to just the first child
        // (the agent glyph), regardless of menuStyle. A plain Button +
        // `.popover` lets us render the full pill-styled "glyph · codex · ⌄"
        // label exactly as designed, and we get visual control over the menu
        // contents too.
        Button {
            agentMenuOpen.toggle()
        } label: {
            HStack(spacing: 6) {
                MarkdownPillAgentDot(agent: agent, size: 14)
                Text(agent.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(MarkdownPillPalette.text)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(MarkdownPillPalette.textMuted)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(MarkdownPillPalette.buttonSurface)
            .overlay(Capsule().stroke(MarkdownPillPalette.border, lineWidth: 1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        // Keep the agent label on a single line even when the pill is narrow;
        // the context and prompt slots truncate before this button wraps.
        .fixedSize(horizontal: true, vertical: false)
        .popover(isPresented: $agentMenuOpen, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(MarkdownPillAgent.allCases) { option in
                    Button {
                        agent = option
                        agentMenuOpen = false
                    } label: {
                        HStack(spacing: 8) {
                            MarkdownPillAgentDot(agent: option, size: 14)
                            Text(option.label)
                                .font(.system(size: 12, weight: .medium))
                            Spacer(minLength: 12)
                            if option == agent {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(MarkdownPillPalette.accent)
                            }
                            Text(option.shortcutHint)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundColor(MarkdownPillPalette.textDim)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .frame(minWidth: 140, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
        }
        .help(compact ? agent.label : "\(agent.label) (\(agent.shortcutHint))")
        .accessibilityLabel(Text(String(localized: "markdownChat.pill.agent.a11y", defaultValue: "Choose CLI agent")))
    }

    private var skillsButton: some View {
        // Clicking opens the slash skills picker by simulating a `/` press.
        // Mirrors what typing `/` does, so the button isn't an inert
        // decoration anymore.
        Button {
            text = "/"
            DispatchQueue.main.async { textFieldFocused = true }
        } label: {
            HStack(spacing: 5) {
                slashGlyph(size: 12)
                Text(String(localized: "markdownChat.pill.button.skills", defaultValue: "skills"))
                    .font(.system(size: 12))
            }
            .foregroundColor(MarkdownPillPalette.textMuted)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(String(localized: "markdownChat.pill.button.skills.a11y",
                                        defaultValue: "Open Brain Skills picker")))
    }

    // mockup's `slash` icon — rounded square with a diagonal line.
    // (SF Symbol "slash.circle" was wrong; mockup is a rect, not a circle.)
    private func slashGlyph(size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22)
                .strokeBorder(MarkdownPillPalette.textMuted, lineWidth: 1.2)
            // Diagonal slash from bottom-left → top-right.
            Path { p in
                let inset: CGFloat = size * 0.18
                p.move(to: CGPoint(x: inset, y: size - inset))
                p.addLine(to: CGPoint(x: size - inset, y: inset))
            }
            .stroke(MarkdownPillPalette.textMuted, style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        }
        .frame(width: size, height: size)
    }

    private func sendButton(enabled: Bool) -> some View {
        Button(action: submit) {
            Image(systemName: "arrow.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Color(red: 20.0 / 255, green: 21.0 / 255, blue: 24.0 / 255))
                .frame(width: 30, height: 30)
                .background(enabled ? MarkdownPillPalette.accent : MarkdownPillPalette.sendDim)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(Text(String(localized: "markdownChat.pill.send.a11y", defaultValue: "Send to agent")))
    }

}
