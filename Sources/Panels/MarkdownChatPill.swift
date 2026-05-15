import AppKit
import SwiftUI

// Floating chat pill overlay for MarkdownPanelView.
//
// Three visual states wired through `isExpanded` × `activeAgent`:
//   - idle (no session, collapsed): "Ask about this doc"
//   - session (CLI pane live, collapsed): "session · agent · Follow up…"
//   - expanded: textfield + chips + agent dropdown + slash skills picker
// Submit / agent change routing is owned by the parent
// `MarkdownPanelView` via the `onSubmit` closure; the pill stays
// presentational. See `MarkdownChatPillCommand` for the shell-side
// invocation contract and `MarkdownChatPillSkillsPicker` for the
// slash-menu UI.

enum MarkdownPillAgent: String, CaseIterable, Identifiable {
    case codex
    case claude
    case gemini

    var id: String { rawValue }

    /// The CLI binary name expected on $PATH. We launch the interactive REPL
    /// of this binary in the spawned terminal and then inject the user's
    /// prompt via socket send_text. See `MarkdownChatPillCommand` for the
    /// full launch + first-prompt protocol.
    var binaryName: String {
        switch self {
        case .codex: return "codex"
        case .claude: return "claude"
        case .gemini: return "gemini"
        }
    }

    var label: String {
        switch self {
        case .codex: return "codex"
        case .claude: return "claude"
        case .gemini: return "gemini"
        }
    }

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

struct MarkdownChatPill: View {
    let displayTitle: String
    /// Non-nil when a CLI session is currently attached to this markdown.
    /// Drives the collapsed "session · agent · Follow up…" rendering and
    /// is set by the parent after a submit kicks off a split pane.
    let activeAgent: MarkdownPillAgent?
    /// Parent handles the actual newTerminalSplit / sendText routing.
    /// The pill just emits the user's intent.
    let onSubmit: (_ text: String, _ agent: MarkdownPillAgent) -> Void

    @State private var isExpanded: Bool = false
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

    private var hasActiveSession: Bool { activeAgent != nil }

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
        displayTitle.isEmpty
            ? String(localized: "markdownChat.pill.chip.thisDoc", defaultValue: "this doc")
            : displayTitle
    }
    private var placeholderText: String {
        String(localized: "markdownChat.pill.placeholder.doc", defaultValue: "Ask about this doc")
    }
    var body: some View {
        Group {
            if isExpanded {
                expandedView
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .bottom)),
                        removal: .opacity
                    ))
            } else if hasActiveSession {
                sessionView
                    .transition(.opacity)
            } else {
                collapsedView
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.22), value: isExpanded)
        .animation(.easeOut(duration: 0.22), value: hasActiveSession)
        .frame(maxWidth: 720)
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
        .onAppear { installSlashKeyMonitor() }
        .onDisappear { removeSlashKeyMonitor() }
    }

    private func expandFromCollapsed() {
        // When re-opening after a session is already active, default the
        // dropdown to the session's agent so a quick follow-up doesn't
        // accidentally spawn a second split via the agent-change path.
        if let activeAgent {
            agent = activeAgent
        }
        isExpanded = true
        DispatchQueue.main.async { textFieldFocused = true }
    }

    private func submit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSubmit(trimmed, agent)
        text = ""
        isExpanded = false
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

    // MARK: - Collapsed (idle)

    private var collapsedView: some View {
        HStack(spacing: 10) {
            contextChip(label: contextChipTitle)

            // ⌘L kbd hint deferred until phase 3 registers a non-conflicting
            // shortcut in KeyboardShortcutSettings — zebra's existing ⌘L
            // already opens a new browser tab.
            //
            // `.layoutPriority(-1)` makes the placeholder the *first* to give
            // up space when the pill gets narrow — the chip (filename) and
            // agent button keep their intrinsic widths, and "Ask about this
            // doc" truncates aggressively (eventually to nothing) before the
            // agent label is forced to wrap.
            Text(placeholderText)
                .font(.system(size: 13.5))
                .foregroundColor(MarkdownPillPalette.textDim)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(-1)

            agentSelectorButton(compact: true)
            sendButton(enabled: false)
        }
        .padding(8)
        .background(MarkdownPillPalette.pillBg)
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(MarkdownPillPalette.borderStrong, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.45), radius: 18, x: 0, y: 18)
        .contentShape(Capsule())
        .onTapGesture { expandFromCollapsed() }
    }

    // MARK: - Session (collapsed, with active CLI pane)

    private var sessionView: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(MarkdownPillPalette.accent)
                    .frame(width: 6, height: 6)
                Text(String(localized: "markdownChat.pill.session.label", defaultValue: "session"))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(MarkdownPillPalette.text)
                Text("·")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(MarkdownPillPalette.textMuted)
                Text(activeAgent?.label ?? "")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(MarkdownPillPalette.textMuted)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(MarkdownPillPalette.accent.opacity(0.10))
            .overlay(Capsule().stroke(MarkdownPillPalette.accent.opacity(0.30), lineWidth: 1))
            .clipShape(Capsule())

            Text(String(localized: "markdownChat.pill.followUpPrompt", defaultValue: "Follow up…"))
                .font(.system(size: 13.5))
                .foregroundColor(MarkdownPillPalette.textDim)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(MarkdownPillPalette.pillBg)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(MarkdownPillPalette.borderStrong, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.45), radius: 18, x: 0, y: 18)
        .contentShape(Capsule())
        .onTapGesture { expandFromCollapsed() }
    }

    // MARK: - Expanded (focused)

    private var expandedView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                contextChip(label: contextChipTitle)
                Text(String(localized: "markdownChat.pill.context.auto", defaultValue: "· auto"))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(MarkdownPillPalette.textDim)
            }

            // multiline TextField (axis: .vertical) gives native placeholder
            // so the cursor and placeholder always align — unlike TextEditor,
            // which has internal text-container insets that don't match a
            // manually-positioned Text overlay. `prompt:` lets us color the
            // placeholder explicitly (default TextField placeholder color is
            // .placeholderText which renders too dark on the dark pill bg).
            // lineLimit(2...6) keeps the input height roughly matching the
            // mockup's rows=2 textarea even when empty.
            // SwiftUI's TextField `prompt:` parameter applies system placeholder
            // dimming on top of any color we set (especially after focus),
            // pushing the visible color far below mockup's `#6c6960`. To
            // keep placeholder color stable across focus states we render it
            // ourselves and feed an empty prompt to the TextField.
            ZStack(alignment: .topLeading) {
                TextField("", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .focused($textFieldFocused)
                    .font(.system(size: 14))
                    .foregroundColor(MarkdownPillPalette.text)
                    .tint(MarkdownPillPalette.accent)
                    .lineLimit(2...6)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                if text.isEmpty {
                    Text(placeholderText)
                        .font(.system(size: 14))
                        .foregroundColor(MarkdownPillPalette.textDim)
                        .allowsHitTesting(false)
                }
            }

            if isSlashMode, let skills = matchingSkills {
                MarkdownChatPillSkillsPicker(
                    skills: skills,
                    slashFilter: slashFilter,
                    selectedIndex: $skillsSelectedIndex,
                    onPick: pickSkill
                )
            }

            Rectangle()
                .fill(MarkdownPillPalette.border)
                .frame(height: 1)
                .padding(.top, 4)

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
        .padding(14)
        .background(MarkdownPillPalette.pillBgExpanded)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18).stroke(MarkdownPillPalette.borderStrong, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.55), radius: 24, x: 0, y: 24)
        .onKeyPress(.escape) {
            if text.isEmpty {
                isExpanded = false
                textFieldFocused = false
                return .handled
            }
            return .ignored
        }
        // ↑/↓ navigate the slash picker; Enter picks. Outside slash mode they
        // pass through to the textfield (newline / caret movement).
        .onKeyPress(.upArrow) {
            guard isSlashMode, let skills = matchingSkills, !skills.isEmpty else { return .ignored }
            skillsSelectedIndex = max(0, skillsSelectedIndex - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard isSlashMode, let skills = matchingSkills, !skills.isEmpty else { return .ignored }
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
            if commitIMECompositionIfNeeded() {
                DispatchQueue.main.async { _ = runEnterAction() }
                return .handled
            }
            return runEnterAction() ? .handled : .ignored
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
        }
        .padding(.leading, 8)
        .padding(.trailing, 10)
        .padding(.vertical, 4)
        .background(MarkdownPillPalette.accent.opacity(0.10))
        .overlay(
            Capsule().stroke(MarkdownPillPalette.accent.opacity(0.25), lineWidth: 1)
        )
        .clipShape(Capsule())
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
        // Keep the agent label on a single line even when the pill is narrow —
        // the placeholder and chip have `.layoutPriority(-1)` / truncation so
        // they shrink first instead of forcing this button to wrap.
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
            isExpanded = true
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
