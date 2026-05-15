import AppKit
import SwiftUI

// Floating chat pill overlay for MarkdownPanelView.
// Phase 1: idle ↔ focused state machine only. No submit, no slash menu,
// no selection capture, no real agent dropdown. Agent button and skills
// button are visual placeholders.

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

/// Builds the shell command that drives a chat-pill session.
enum MarkdownChatPillCommand {
    /// Prepare any agent-specific launch state that cannot be expressed as a
    /// safe session-scoped CLI flag. Returns false when preparation failed and
    /// the agent should fall back to its own first-run prompt.
    static func prepareLaunchEnvironment(agent: MarkdownPillAgent, markdownFilePath: String) -> Bool {
        let parent = (markdownFilePath as NSString).deletingLastPathComponent
        let cwd = parent.isEmpty ? "/" : parent
        switch agent {
        case .codex:
            return true
        case .claude:
            return markClaudeProjectTrusted(cwd: cwd)
        case .gemini:
            return true
        }
    }

    static func shellStartupLine(
        agent: MarkdownPillAgent,
        markdownFilePath: String,
        userPrompt: String,
        selection: MarkdownChatPillSelection? = nil
    ) -> String {
        let parent = (markdownFilePath as NSString).deletingLastPathComponent
        let cwd = parent.isEmpty ? "/" : parent
        return "\(invocation(agent: agent, cwd: cwd, markdownFilePath: markdownFilePath, prompt: userPrompt, selection: selection))\r"
    }

    /// Per-agent CLI invocation tuned to keep the initial prompt on the agent
    /// path instead of a first-run trust dialog. Codex uses a per-process
    /// config override, Gemini uses its official session-scoped `--skip-trust`
    /// flag, and Claude relies on `prepareLaunchEnvironment` to pre-accept the
    /// current cwd in Claude's project state when that file is writable.
    private static func invocation(
        agent: MarkdownPillAgent,
        cwd: String,
        markdownFilePath: String,
        prompt: String,
        selection: MarkdownChatPillSelection?
    ) -> String {
        let promptArgument = singleLineShellArgument(prompt)
        let fileContext = "Use this markdown file as context: \(markdownFilePath)"
        let selectionContext = selection.map { selectionNote(for: $0) }
        // Visible context = what we want the agent to *see in the user message*
        // (file + optional selection + user's question). Compressed to one
        // line so shell single-quoting is straightforward.
        let visibleParts: [String] = [fileContext + ".", selectionContext.map { $0 + "." }, promptArgument]
            .compactMap { $0 }
        let visibleContextPrompt = visibleParts.joined(separator: " ")
        // Hidden system-prompt variant for claude's --append-system-prompt:
        // same file + selection note, but without the user message tacked on
        // (claude takes the user prompt separately).
        let hiddenParts: [String] = [fileContext, selectionContext].compactMap { $0 }
        let hiddenContextInstruction = hiddenParts.joined(separator: ". ")
        switch agent {
        case .codex:
            let override = "projects.\"\(cwd)\".trust_level=\"trusted\""
            return "cd \(shellQuote(cwd)) && codex -c \(shellQuote(override)) \(shellQuote(visibleContextPrompt))"
        case .claude:
            return "cd \(shellQuote(cwd)) && claude --append-system-prompt \(shellQuote(hiddenContextInstruction)) \(shellQuote(promptArgument))"
        case .gemini:
            return "cd \(shellQuote(cwd)) && gemini --skip-trust --prompt-interactive \(shellQuote(visibleContextPrompt))"
        }
    }

    /// One-line sentence describing the user's excerpt selection — used both
    /// as the visible context (codex/gemini) and the system-prompt note
    /// (claude). Heading is included when we managed to back-resolve it.
    private static func selectionNote(for selection: MarkdownChatPillSelection) -> String {
        let excerpt = selection.fullExcerpt
        if let heading = selection.heading {
            return "The user selected this excerpt from the section titled \u{201C}\(heading)\u{201D}: \u{201C}\(excerpt)\u{201D}"
        }
        return "The user selected this excerpt from the markdown: \u{201C}\(excerpt)\u{201D}"
    }

    /// Follow-up text for an already-running session. Do not append Return:
    /// agent TUIs disagree about whether synthetic Return submits or inserts a
    /// newline, so we only type the text and let the user press Enter.
    static func followUpPrompt(userPrompt: String) -> String {
        userPrompt
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func singleLineShellArgument(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    private static func markClaudeProjectTrusted(cwd: String) -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
        guard var root = readJSONObjectIfPresent(at: url) else {
            return false
        }
        var projects = root["projects"] as? [String: Any] ?? [:]
        var project = projects[cwd] as? [String: Any] ?? [:]
        project["hasTrustDialogAccepted"] = true
        projects[cwd] = project
        root["projects"] = projects
        return writeJSONObject(root, to: url)
    }

    private static func readJSONObjectIfPresent(at url: URL) -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return [:]
        }
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private static func writeJSONObject(_ object: [String: Any], to url: URL) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            return false
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}

/// A snapshot of the user's text selection inside the markdown body, used to
/// drive the yellow selection chip in the pill and to embed an excerpt /
/// heading hint into the agent's first prompt.
///
/// Designed as a pure value type so the parent (`MarkdownPanelView`) can
/// build/replace/clear instances when its NSTextView selection observer fires,
/// without the pill needing to know about NSTextView at all.
struct MarkdownChatPillSelection: Equatable {
    /// Whitespace-collapsed, single-line text, truncated to <= 500 chars with
    /// an ellipsis. This is the form we embed in the CLI prompt argument so
    /// the agent gets the excerpt verbatim regardless of original newlines.
    let fullExcerpt: String
    /// Original character count of the raw selection (before truncation /
    /// whitespace collapse). Shown in the chip label as "N chars".
    let chars: Int
    /// Number of newline-separated lines in the raw selection.
    let lines: Int
    /// Nearest preceding markdown heading (`## State`, `### ...`) of the
    /// selection's location in the source — nil when the selection sits
    /// above all headings, or when the heading lookup fails (e.g., the
    /// rendered text doesn't match the source verbatim).
    let heading: String?

    /// Build a snapshot from raw selected text and the panel's source. Returns
    /// nil when the selection is too short (< 3 chars after a whitespace
    /// trim) — matches the mockup's behavior (mouseup with < 3 chars is a
    /// stray click, not a meaningful selection).
    static func capture(rawText: String, in panelContent: String) -> MarkdownChatPillSelection? {
        let collapsed = rawText
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard collapsed.count >= 3 else { return nil }

        let chars = rawText.count
        let lines = rawText
            .components(separatedBy: CharacterSet.newlines)
            .count
        let heading = nearestPrecedingHeading(of: rawText, in: panelContent)
        let excerptCap = 500
        let fullExcerpt = collapsed.count > excerptCap
            ? String(collapsed.prefix(excerptCap - 1)) + "\u{2026}"
            : collapsed
        return .init(
            fullExcerpt: fullExcerpt,
            chars: chars,
            lines: lines,
            heading: heading
        )
    }

    /// Shorter form used in the chip UI (italic quote). The mockup caps the
    /// chip excerpt at 110 chars; the full 500-char form is reserved for the
    /// prompt that actually reaches the agent.
    var displayExcerpt: String {
        let cap = 110
        guard fullExcerpt.count > cap else { return fullExcerpt }
        return String(fullExcerpt.prefix(cap - 2)) + "\u{2026}"
    }

    /// Walk back from the selection's substring start in the source content
    /// to find the most recent `#` / `##` / ... line. Best-effort — if the
    /// rendered selection text doesn't appear verbatim in the source (e.g.,
    /// MarkdownUI stripped emphasis markers) we just return nil and the chip
    /// renders without a heading.
    private static func nearestPrecedingHeading(of selection: String, in content: String) -> String? {
        let trimmedSelection = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSelection.isEmpty,
              let range = content.range(of: trimmedSelection) else { return nil }
        let prefix = content[..<range.lowerBound]
        for line in prefix.split(separator: "\n", omittingEmptySubsequences: false).reversed() {
            let stripped = line.trimmingCharacters(in: .whitespaces)
            guard stripped.hasPrefix("#") else { continue }
            let title = stripped.drop(while: { $0 == "#" })
                .trimmingCharacters(in: .whitespaces)
            if !title.isEmpty { return title }
        }
        return nil
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
private enum MarkdownPillPalette {
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
}

struct MarkdownChatPill: View {
    let displayTitle: String
    /// Non-nil when a CLI session is currently attached to this markdown.
    /// Drives the collapsed "session · agent · Follow up…" rendering and
    /// is set by the parent after a submit kicks off a split pane.
    let activeAgent: MarkdownPillAgent?
    /// Non-nil when the user has highlighted a chunk of the markdown body.
    /// Drives the yellow selection chip + placeholder swap to "Ask about
    /// this selection". Cleared via `onClearSelection` when the user hits
    /// the chip's × button.
    let activeSelection: MarkdownChatPillSelection?
    /// Parent handles the actual newTerminalSplit / sendText routing.
    /// The pill just emits the user's intent (and the active selection).
    let onSubmit: (_ text: String, _ agent: MarkdownPillAgent) -> Void
    /// Invoked when the user clicks the × on the selection chip. Parent
    /// drops the selection snapshot; the underlying NSTextView highlight is
    /// intentionally left alone (plan §C).
    let onClearSelection: () -> Void

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
    private var hasActiveSelection: Bool { activeSelection != nil }
    private var contextChipTitle: String {
        displayTitle.isEmpty
            ? String(localized: "markdownChat.pill.chip.thisDoc", defaultValue: "this doc")
            : displayTitle
    }
    private var placeholderText: String {
        hasActiveSelection
            ? String(localized: "markdownChat.pill.placeholder.selection", defaultValue: "Ask about this selection")
            : String(localized: "markdownChat.pill.placeholder.doc", defaultValue: "Ask about this doc")
    }
    private static let selectionTint = Color(red: 232.0 / 255, green: 183.0 / 255, blue: 92.0 / 255)

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
        // Drag-to-expand: when a brand-new selection arrives from the
        // markdown body, automatically open the pill and put focus into the
        // text field so the user can type their question immediately — same
        // behavior as the mockup's mouseup → pill expand flow.
        .onChange(of: activeSelection) { _, newValue in
            guard newValue != nil, !isExpanded else { return }
            isExpanded = true
            DispatchQueue.main.async { textFieldFocused = true }
        }
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
            guard isExpanded,
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
                let safeIndex = min(max(0, skillsSelectedIndex), skills.count - 1)
                pickSkill(skills[safeIndex])
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

            if let selection = activeSelection {
                collapsedSelectionChip(chars: selection.chars)
            }
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
                if let selection = activeSelection {
                    expandedSelectionChip(selection)
                }
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
                skillsPicker(skills: skills)
            }

            Rectangle()
                .fill(MarkdownPillPalette.border)
                .frame(height: 1)
                .padding(.top, 4)

            HStack(spacing: 6) {
                skillsButtonPlaceholder

                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    kbdLabel("↵")
                    Text(String(localized: "markdownChat.pill.footer.run", defaultValue: " run · "))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(MarkdownPillPalette.textDim)
                    kbdLabel("⇧↵")
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
        // TextField(axis: .vertical) treats Enter as newline by default.
        // Plain ⏎ submits, ⇧⏎ keeps the newline behavior (the field uses
        // its built-in shift-modified handling so we only need to intercept
        // the un-shifted case). When the slash picker is open, ⏎ picks the
        // highlighted skill instead of submitting.
        .onKeyPress(.return) {
            if isSlashMode, let skills = matchingSkills, !skills.isEmpty {
                let safeIndex = min(max(0, skillsSelectedIndex), skills.count - 1)
                pickSkill(skills[safeIndex])
                return .handled
            }
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                submit()
                return .handled
            }
            return .ignored
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

    /// Compact "N chars selected" chip for the collapsed pill row. mockup
    /// uses this in the resting state when a selection exists; it stays
    /// short so the placeholder text still has room next to it.
    private func collapsedSelectionChip(chars: Int) -> some View {
        let tint = Self.selectionTint
        return HStack(spacing: 6) {
            Image(systemName: "number")
                .font(.system(size: 10))
                .foregroundColor(tint)
            Text(String(format: String(localized: "markdownChat.pill.chip.selection.chars",
                                       defaultValue: "%d chars"), chars))
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundColor(MarkdownPillPalette.text)
            Button(action: onClearSelection) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(MarkdownPillPalette.textMuted)
                    .padding(2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(String(localized: "markdownChat.pill.chip.selection.clear.a11y",
                                            defaultValue: "Clear selection")))
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background(tint.opacity(0.13))
        .overlay(Capsule().stroke(tint.opacity(0.35), lineWidth: 1))
        .clipShape(Capsule())
        .fixedSize(horizontal: true, vertical: false)
    }

    /// Richer chip used inside the expanded pill — mirrors mockup
    /// `SelectionChip`: hash + uppercase label row (SELECTION · # Heading ·
    /// N chars) plus a 2-line italic quote of the excerpt, with the same
    /// × button to clear.
    private func expandedSelectionChip(_ selection: MarkdownChatPillSelection) -> some View {
        let tint = Self.selectionTint
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: "number")
                .font(.system(size: 11))
                .foregroundColor(tint)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(String(localized: "markdownChat.pill.chip.selection.label",
                                defaultValue: "SELECTION"))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(tint)
                        .kerning(0.8)
                    if let heading = selection.heading {
                        Text("·")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(MarkdownPillPalette.textMuted)
                        Text(heading)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(MarkdownPillPalette.textMuted)
                            .lineLimit(1)
                    }
                    Text("·")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(MarkdownPillPalette.textDim)
                    Text(String(format: String(localized: "markdownChat.pill.chip.selection.chars",
                                                defaultValue: "%d chars"), selection.chars))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(MarkdownPillPalette.textDim)
                }
                Text("\u{201C}\(selection.displayExcerpt)\u{201D}")
                    .font(.system(size: 11.5).italic())
                    .foregroundColor(MarkdownPillPalette.text)
                    .lineLimit(2)
                    .frame(maxWidth: 320, alignment: .leading)
            }
            Button(action: onClearSelection) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(MarkdownPillPalette.textMuted)
                    .padding(2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(String(localized: "markdownChat.pill.chip.selection.clear.a11y",
                                            defaultValue: "Clear selection")))
        }
        .padding(.leading, 9)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
        .background(tint.opacity(0.10))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(tint.opacity(0.30), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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

    /// Glyph pool from mockup `md-app.jsx::SKILLS`. gbrain's manifest doesn't
    /// ship per-skill glyphs, so we deterministically hash the skill name to
    /// a glyph for stable visuals across launches.
    private static let skillGlyphs: [String] = ["✦", "◐", "◇", "▲", "★", "✓", "↗"]

    private func glyph(for skillName: String) -> String {
        let bucket = abs(skillName.hashValue) % Self.skillGlyphs.count
        return Self.skillGlyphs[bucket]
    }

    @ViewBuilder
    private func skillsPicker(skills: [BrainSkillsManifest.Skill]) -> some View {
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
                kbdLabel("↑↓")
                kbdLabel("↵")
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
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(skills.enumerated()), id: \.element.id) { index, skill in
                            skillRow(skill: skill, isSelected: index == skillsSelectedIndex)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.03))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(MarkdownPillPalette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func skillRow(skill: BrainSkillsManifest.Skill, isSelected: Bool) -> some View {
        // mockup's `SKILLS` data ships per-row scope; the project rows use a
        // warm yellow (#e8b75c) for both the glyph tile and the badge. gbrain
        // doesn't carry a scope so we surface every row in the yellow tone —
        // matches the visual reference the user is comparing against
        // (mockup screenshot of /plan-pr, /ship-checklist, /sync-linear).
        let tint = Self.selectionTint
        return Button {
            pickSkill(skill)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Text(glyph(for: skill.name))
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
    }

    private var skillsButtonPlaceholder: some View {
        Button(action: {}) {
            HStack(spacing: 5) {
                slashGlyph(size: 12)
                Text(String(localized: "markdownChat.pill.button.skills", defaultValue: "skills"))
                    .font(.system(size: 12))
            }
            .foregroundColor(MarkdownPillPalette.textMuted)
        }
        .buttonStyle(.plain)
        // Phase 1 placeholder — skills picker wired in phase 4.
        .accessibilityHidden(true)
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

    private func kbdLabel(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundColor(MarkdownPillPalette.textMuted)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}
