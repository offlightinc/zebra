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
    /// The text we synthetically type into a freshly-opened shell pane.
    ///
    /// The first prompt is passed through each agent's initial-prompt path
    /// instead of being injected into the agent TUI after startup.
    static func prepareLaunchEnvironment(agent: MarkdownPillAgent, markdownFilePath: String) {
        let parent = (markdownFilePath as NSString).deletingLastPathComponent
        let cwd = parent.isEmpty ? "/" : parent
        switch agent {
        case .codex:
            break
        case .claude:
            markClaudeProjectTrusted(cwd: cwd)
        case .gemini:
            break
        }
    }

    static func shellStartupLine(
        agent: MarkdownPillAgent,
        markdownFilePath: String,
        userPrompt: String
    ) -> String {
        let parent = (markdownFilePath as NSString).deletingLastPathComponent
        let cwd = parent.isEmpty ? "/" : parent
        return "\(invocation(agent: agent, cwd: cwd, markdownFilePath: markdownFilePath, prompt: userPrompt))\r"
    }

    /// Per-agent CLI invocation tuned to skip first-run interactive prompts
    /// that would otherwise swallow the auto-injected first message.
    ///
    /// codex shows a "Do you trust this directory?" prompt the first time
    /// it runs in a new cwd; while that prompt is up, anything we send via
    /// send_text lands on the trust dialog instead of the model. We pre-mark
    /// the cwd as trusted via a per-invocation `-c` override so the prompt
    /// never appears. The user's persistent `~/.codex/config.toml` is not
    /// modified — the override applies only to this process.
    private static func invocation(
        agent: MarkdownPillAgent,
        cwd: String,
        markdownFilePath: String,
        prompt: String
    ) -> String {
        let promptArgument = singleLineShellArgument(prompt)
        let visibleContextPrompt = "Use this markdown file as context: \(markdownFilePath). \(promptArgument)"
        let hiddenContextInstruction = "Use this markdown file as context: \(markdownFilePath)"
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

    private static func markClaudeProjectTrusted(cwd: String) {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")
        var root = readJSONObject(at: url)
        var projects = root["projects"] as? [String: Any] ?? [:]
        var project = projects[cwd] as? [String: Any] ?? [:]
        project["hasTrustDialogAccepted"] = true
        projects[cwd] = project
        root["projects"] = projects
        writeJSONObject(root, to: url)
    }

    private static func readJSONObject(at url: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object
    }

    private static func writeJSONObject(_ object: [String: Any], to url: URL) {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
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
    /// Parent handles the actual newTerminalSplit / sendText routing.
    /// The pill just emits the user's intent.
    let onSubmit: (_ text: String, _ agent: MarkdownPillAgent) -> Void

    @State private var isExpanded: Bool = false
    @State private var text: String = ""
    @State private var agent: MarkdownPillAgent = .codex
    @State private var agentMenuOpen: Bool = false
    @FocusState private var textFieldFocused: Bool

    private var hasActiveSession: Bool { activeAgent != nil }
    private var contextChipTitle: String {
        displayTitle.isEmpty
            ? String(localized: "markdownChat.pill.chip.thisDoc", defaultValue: "this doc")
            : displayTitle
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
            Text(String(localized: "markdownChat.pill.placeholder.doc", defaultValue: "Ask about this doc"))
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
            HStack(spacing: 6) {
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
                    Text(String(localized: "markdownChat.pill.placeholder.doc", defaultValue: "Ask about this doc"))
                        .font(.system(size: 14))
                        .foregroundColor(MarkdownPillPalette.textDim)
                        .allowsHitTesting(false)
                }
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
        // TextField(axis: .vertical) treats Enter as newline by default.
        // Plain ⏎ submits, ⇧⏎ keeps the newline behavior (the field uses
        // its built-in shift-modified handling so we only need to intercept
        // the un-shifted case).
        .onKeyPress(.return) {
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
