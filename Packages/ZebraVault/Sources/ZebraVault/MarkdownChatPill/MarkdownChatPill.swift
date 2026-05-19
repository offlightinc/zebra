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
    /// NSEvent monitor token used to intercept ↑/↓/⏎ ahead of the
    /// focused TextField while the slash picker is open. SwiftUI's
    /// `.onKeyPress(.upArrow)` on an outer container is preempted by the
    /// focused TextField's caret-movement handling, so we run the monitor
    /// at the local NSEvent level instead. Lifecycle is tied to the pill
    /// existing in the view tree.
    @State private var slashKeyMonitor: Any?
    @FocusState private var textFieldFocused: Bool

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
        .onAppear {
            installSlashKeyMonitor()
        }
        .onDisappear {
            removeSlashKeyMonitor()
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
        .onKeyPress(.escape) {
            if isExpanded, text.isEmpty {
                collapse()
                return .handled
            }
            return .ignored
        }
        // ↑/↓ navigate the slash picker; Enter picks. Outside slash mode they
        // pass through to the textfield (newline / caret movement).
        .onKeyPress(.upArrow) {
            guard isExpanded, isSlashMode, let skills = matchingSkills, !skills.isEmpty else { return .ignored }
            skillsSelectedIndex = max(0, skillsSelectedIndex - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard isExpanded, isSlashMode, let skills = matchingSkills, !skills.isEmpty else { return .ignored }
            skillsSelectedIndex = min(skills.count - 1, skillsSelectedIndex + 1)
            return .handled
        }
        // ⏎ submits (or picks a slash skill). When an IME is mid-
        // composition we first force-commit its marked text and sync our
        // @State `text` directly from the NSTextView, then re-evaluate
        // the action on the next runloop tick so the slash-mode / submit
        // gate sees the post-commit string.
        //
        // POLICY: one Enter == commit-and-submit. We intentionally do *not*
        // adopt the native-macOS "first Enter commits, second Enter
        // submits" pattern (Slack/Discord-style). Most pill traffic is
        // one-shot prompts where the user types and immediately wants to
        // send — making them press Enter twice is friction. If we ever
        // want the two-step variant, return `.handled` from the IME
        // branch without scheduling `runEnterAction()`.
        .onKeyPress(.return) {
            guard isExpanded else { return .ignored }
            if commitIMECompositionIfNeeded() {
                DispatchQueue.main.async { _ = runEnterAction() }
                return .handled
            }
            return runEnterAction() ? .handled : .ignored
        }
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
            textFieldFocused = true
            // macOS TextField selects-all on first-responder grant; when
            // we're re-expanding with preserved text the user expects a
            // caret at the end, not a wholesale selection that the next
            // keystroke would destroy.
            DispatchQueue.main.async { moveCaretToEnd() }
        }
    }

    private func collapse() {
        textFieldFocused = false
        withAnimation(Self.motion) {
            isExpanded = false
        }
    }

    /// Move the focused NSTextView's caret to the end of its content,
    /// collapsing any selection. Safe no-op when our pill isn't the
    /// first responder.
    ///
    /// `textFieldFocused` guards the multi-pill case: if the user
    /// clicked into a different pill in the same window before our
    /// deferred dispatch fired, that pill now owns first-responder and
    /// we'd otherwise mutate its selection.
    private func moveCaretToEnd() {
        guard textFieldFocused,
              let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
        let end = (textView.string as NSString).length
        textView.setSelectedRange(NSRange(location: end, length: 0))
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSubmit(trimmed, agent)
        text = ""
        collapse()
        textFieldFocused = false
    }

    // MARK: - Slash key monitor

    /// Register a local NSEvent monitor so ↑/↓/⏎ go to the slash picker
    /// instead of the focused TextField while the slash menu is open. We
    /// fall back to passing the event through whenever the picker is not
    /// active so normal typing (caret movement, newline) keeps working.
    private func installSlashKeyMonitor() {
        guard slashKeyMonitor == nil else { return }
        slashKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // `NSEvent.addLocalMonitorForEvents` is process-wide, so we
            // gate on @FocusState `textFieldFocused` — our TextField has
            // first-responder ownership only while it's actually focused.
            // If the user is typing in another textfield (sidebar search,
            // a different markdown panel's pill, etc.) the event passes
            // through unmodified. Not a perfect defense (focus state can
            // momentarily lag) but matches the actual user-intent gate.
            guard isExpanded,
                  textFieldFocused,
                  isSlashMode,
                  let skills = matchingSkills,
                  !skills.isEmpty else {
                return event
            }
            switch event.keyCode {
            case 126: // up arrow
                skillsSelectedIndex = max(0, skillsSelectedIndex - 1)
                return nil
            case 125: // down arrow
                skillsSelectedIndex = min(skills.count - 1, skillsSelectedIndex + 1)
                return nil
            case 36, 76: // return / numpad enter
                // Same commit-then-pick dance as `.onKeyPress(.return)`,
                // routed through the shared helpers so both paths stay in
                // lockstep (IME commit + `runEnterAction()` re-evaluation).
                if commitIMECompositionIfNeeded() {
                    DispatchQueue.main.async { _ = runEnterAction() }
                    return nil
                }
                _ = runEnterAction()
                return nil
            default:
                return event
            }
        }
    }

    private func removeSlashKeyMonitor() {
        if let monitor = slashKeyMonitor {
            NSEvent.removeMonitor(monitor)
            slashKeyMonitor = nil
        }
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
        // multiline TextField (axis: .vertical) gives native placeholder
        // so the cursor and placeholder always align — unlike TextEditor,
        // which has internal text-container insets that don't match a
        // manually-positioned Text overlay. SwiftUI's TextField `prompt:`
        // also applies system dimming on top of custom colors, so we render
        // the placeholder ourselves.
        ZStack(alignment: .topLeading) {
            TextField("", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .focused($textFieldFocused)
                .font(.system(size: 14))
                .foregroundColor(MarkdownPillPalette.text)
                .tint(MarkdownPillPalette.accent)
                .lineLimit(2...2)
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

    /// Pick a slash skill if the picker is open, otherwise submit the
    /// current prompt. Returns `true` when something happened (so the
    /// caller can mark the key event handled). Hoisted out of the
    /// `.onKeyPress(.return)` closure so the IME commit path can reuse it
    /// after deferring one runloop tick.
    ///
    /// Re-evaluates `isSlashMode` / `matchingSkills` from current state
    /// instead of capturing them — the IME commit may have changed the
    /// text (e.g., committing a space ended slash mode), so the deferred
    /// caller must see the latest values.
    private func runEnterAction() -> Bool {
        if isSlashMode, let skills = matchingSkills, !skills.isEmpty {
            let safeIndex = min(max(0, skillsSelectedIndex), skills.count - 1)
            pickSkill(skills[safeIndex])
            return true
        }
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            submit()
            return true
        }
        return false
    }

    /// If the focused NSTextView is mid-IME-composition (marked text not
    /// yet committed), force-commit it via `unmarkText()` and sync our
    /// `text` @State directly from the view's storage so the next
    /// `runEnterAction()` call reads the post-commit string regardless of
    /// SwiftUI binding propagation timing. Returns `true` when a commit
    /// happened (caller should defer the follow-up action one tick).
    @discardableResult
    private func commitIMECompositionIfNeeded() -> Bool {
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
              isFirstResponderComposingIME() else {
            return false
        }
        textView.unmarkText()
        // Pull the committed string straight from the text view rather
        // than waiting for SwiftUI's TextField binding to catch up — the
        // binding usually propagates on the next runloop, but "usually"
        // is not "always", and a missed propagation silently loses a
        // syllable from the prompt.
        text = textView.string
        return true
    }

    /// True when the focused NSTextView is *actively composing inside an
    /// IME* (Korean Hangul jamo waiting to combine, Pinyin candidate, etc.).
    /// We only run the commit path in that case — a pure keylayout source
    /// never produces composition state, and we observed `hasMarkedText()`
    /// false-positives on English input that swallowed every Enter.
    ///
    /// NOTE: the `com.apple.inputmethod.*` substring check is a heuristic
    /// against a private-ish identifier. Third-party IMEs may use other
    /// prefixes. The deeper fix is to identify whether the queried
    /// NSTextView is genuinely ours (responder-chain or hosting-view
    /// ancestry check) — same multi-panel scoping problem we have in the
    /// selection observer. Kept as a defensive filter until then.
    private func isFirstResponderComposingIME() -> Bool {
        guard textFieldFocused,
              let textView = NSApp.keyWindow?.firstResponder as? NSTextView else {
            return false
        }
        guard let sourceID = textView.inputContext?.selectedKeyboardInputSource,
              sourceID.contains("inputmethod") else {
            return false
        }
        return textView.hasMarkedText()
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
