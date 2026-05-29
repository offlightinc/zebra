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
        case .antigravity: return "⌥3"
        }
    }

    /// Two-line description shown under the label in the picker. Matches
    /// md-app.jsx's `AGENTS.desc` strings — "vendor · tagline" monospace.
    var desc: String {
        switch self {
        case .codex: return "OpenAI · code-first"
        case .claude: return "Anthropic · reasoning"
        case .antigravity: return "Google · Antigravity"
        }
    }

    // Mockup-faithful (placeholder marks, not real brands) — md-chat.jsx::AgentDot
    var glyph: String {
        switch self {
        case .codex: return "◇"
        case .claude: return "✳"
        case .antigravity: return "✦"
        }
    }

    var glyphBg: Color {
        switch self {
        case .codex: return Color(red: 15.0 / 255, green: 15.0 / 255, blue: 15.0 / 255)
        case .claude: return Color(red: 201.0 / 255, green: 100.0 / 255, blue: 66.0 / 255)
        case .antigravity: return Color(red: 42.0 / 255, green: 77.0 / 255, blue: 173.0 / 255)
        }
    }

    var glyphColor: Color {
        switch self {
        case .codex: return Color(red: 230.0 / 255, green: 228.0 / 255, blue: 221.0 / 255)
        case .claude, .antigravity: return .white
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

/// Rich agent row used inside the chat pill's agent picker popover.
/// Mirrors md-app.jsx::AgentSelector dropdown rows:
///   [dot]  label              [⌥1]
///          vendor · tagline
/// Active row tints its background with the accent mint.
fileprivate struct MarkdownPillAgentMenuRow: View {
    let agent: MarkdownPillAgent
    let active: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            MarkdownPillAgentDot(agent: agent, size: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(agent.label)
                    .font(.system(size: 12.5))
                    .foregroundColor(MarkdownPillPalette.text)
                Text(agent.desc)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(MarkdownPillPalette.textDim)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            MarkdownPillKbd(text: agent.shortcutHint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(active ? MarkdownPillPalette.accent.opacity(0.10) : .clear)
        )
        .contentShape(Rectangle())
    }
}

/// Mockup-faithful kbd chip — small monospace label inside a faint
/// white-tinted rounded rect.
fileprivate struct MarkdownPillKbd: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundColor(MarkdownPillPalette.textMuted)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.white.opacity(0.08))
                    )
            )
    }
}

/// SwiftUI's native `.popover` on macOS auto-dismisses on outside clicks,
/// but the custom overlay-based dropdowns used by the chat pill and the
/// email connect picker don't. This modifier installs a local NSEvent
/// `.leftMouseUp` monitor while `isPresented` is true, then closes the
/// menu on the next-frame run-loop tick. Buttons inside the dropdown
/// rows fire their actions before the async closure runs (and set
/// `isPresented = false` themselves), so the closure becomes a no-op for
/// hits inside the menu. Outside clicks land in nothing else, so the
/// closure does the dismiss.
struct DismissOnOutsideMouseUp: ViewModifier {
    @Binding var isPresented: Bool
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented) { _, open in
                if open { install() } else { remove() }
            }
            .onDisappear { remove() }
    }

    private func install() {
        remove()
        // chip click 의 자기 mouseUp 까지 monitor 가 catch 해서 dropdown 이 즉시
        // 다시 닫히는 race 회피 — install 자체를 next run loop tick 으로 미룸.
        // 그 사이 trigger button 의 mouseUp 은 이미 dispatch 되어 무사. 그 다음
        // mouseUp 부터 catch.
        DispatchQueue.main.async {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { event in
                DispatchQueue.main.async {
                    if isPresented {
                        isPresented = false
                    }
                }
                return event
            }
        }
    }

    private func remove() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }
}

extension View {
    func dismissOnOutsideMouseUp(isPresented: Binding<Bool>) -> some View {
        modifier(DismissOnOutsideMouseUp(isPresented: isPresented))
    }
}

/// Captures the chat pill agent picker trigger button's bounds so the
/// dropdown can be rendered at the body level (outside `pillShell`'s
/// `clipShape(RoundedRectangle)` that would otherwise truncate the popup
/// trying to extend above the pill).
///
/// `fileprivate` on purpose — the email sidebar has its own
/// `EmailAgentButtonAnchorKey` so the two view trees can never leak
/// anchors into each other if one is ever nested inside the other.
fileprivate struct AgentButtonAnchorKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
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
    /// Slightly more opaque variant for floating popovers (agent picker
    /// dropdown). Matches md-app.jsx::dropdown's `rgba(20,21,24,0.98)`
    /// — the dropdown sits over the markdown content and benefits from
    /// the extra contrast vs. the pill itself.
    static let popoverBg = Color(red: 20.0 / 255, green: 21.0 / 255, blue: 24.0 / 255).opacity(0.98)
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

public enum MarkdownChatPillLayout {
    public static let maxWidth: CGFloat = 720
    public static let collapsedHeight: CGFloat = 46
    public static let collapsedContentHeight: CGFloat = 30
    public static let baseInputHeight: CGFloat = 38
    public static let expandedHeight: CGFloat = 156
    public static let maxExpandedInputHeight: CGFloat = 112
    /// Slot height the pill grows by when the slash picker is open.
    /// Matches the picker's own maxHeight (200 for the scroll area) plus
    /// header (~24), inner padding (~10), and the spacing between input
    /// and picker (~8). Conservative so a fully-populated picker doesn't
    /// overflow the pill.
    public static let skillsPickerSlotHeight: CGFloat = 244
    public static let floatingBottomPadding: CGFloat = 22
    public static let baseContentBottomInset: CGFloat = 160
    public static let minimumVisibleContentHeight: CGFloat = 120

    public static var maxExpandedHeight: CGFloat {
        expandedHeight + max(0, maxExpandedInputHeight - baseInputHeight)
    }

    public static func maxShellHeight(availableContentHeight: CGFloat?) -> CGFloat {
        guard let availableContentHeight,
              availableContentHeight.isFinite,
              availableContentHeight > 0 else {
            return maxExpandedHeight
        }

        let panelAwareMax = availableContentHeight - floatingBottomPadding - minimumVisibleContentHeight
        return min(maxExpandedHeight, max(expandedHeight, panelAwareMax))
    }

    public static func inputHeight(
        measuredContentHeight: CGFloat,
        availableContentHeight: CGFloat?
    ) -> CGFloat {
        let measuredHeight = measuredContentHeight.isFinite
            ? measuredContentHeight.rounded(.up)
            : baseInputHeight
        let desiredHeight = max(baseInputHeight, measuredHeight)
        let shellHeightCap = maxShellHeight(availableContentHeight: availableContentHeight)
        let inputHeightCap = max(baseInputHeight, baseInputHeight + shellHeightCap - expandedHeight)
        return min(desiredHeight, inputHeightCap)
    }

    public static func shellHeight(
        isExpanded: Bool,
        pickerOpen: Bool,
        inputHeight: CGFloat
    ) -> CGFloat {
        guard isExpanded else { return collapsedHeight }
        let normalHeight = expandedHeight + max(0, inputHeight - baseInputHeight)
        return pickerOpen ? normalHeight + skillsPickerSlotHeight : normalHeight
    }

    public static func contentBottomInset(shellHeight: CGFloat) -> CGFloat {
        baseContentBottomInset + max(0, shellHeight - expandedHeight)
    }
}

public struct MarkdownChatPill: View {
    private static let expandedChipMaxWidth: CGFloat = 320
    private static let motion = Animation.timingCurve(0.4, 0.0, 0.2, 1.0, duration: 0.30)

    let displayTitle: String
    let availableContentHeight: CGFloat?
    /// Non-nil when this markdown already has a companion pane for agent
    /// tabs. Submit still creates a fresh terminal tab; this only changes
    /// the collapsed affordance.
    let activeAgent: MarkdownPillAgent?
    /// Parent handles the actual split/tab creation and terminal input.
    /// The pill just emits the user's intent.
    let onSubmit: (_ text: String, _ agent: MarkdownPillAgent) -> Void
    let onHeightChange: ((CGFloat) -> Void)?

    public init(
        isExpanded: Binding<Bool>,
        displayTitle: String,
        availableContentHeight: CGFloat? = nil,
        activeAgent: MarkdownPillAgent?,
        onSubmit: @escaping (_ text: String, _ agent: MarkdownPillAgent) -> Void,
        onHeightChange: ((CGFloat) -> Void)? = nil
    ) {
        self._isExpanded = isExpanded
        self.displayTitle = displayTitle
        self.availableContentHeight = availableContentHeight
        self.activeAgent = activeAgent
        self.onSubmit = onSubmit
        self.onHeightChange = onHeightChange
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
    @State private var measuredInputContentHeight: CGFloat = MarkdownChatPillLayout.baseInputHeight
    @State private var inputHeight: CGFloat = MarkdownChatPillLayout.baseInputHeight

    /// True while the user is mid-slash — input begins with `/` and has no
    /// whitespace yet, so we can offer skill completions. Once they type a
    /// space the slash command is "committed" and the picker hides.
    ///
    /// Driven by `onChange(of: text)` so its toggles can be wrapped in
    /// `withAnimation(Self.motion)`. A pure computed property derived
    /// from `text` would change implicitly during typing, which SwiftUI's
    /// `.animation(_:value:)` doesn't reliably catch for nested
    /// frame/transition mutations — so the pill height step was popping
    /// instead of easing.
    @State private var isSlashMode: Bool = false

    /// Recompute `isSlashMode` from the canonical text-prefix rule. Used
    /// from `onChange(of: text)` so we can wrap the toggle in
    /// `withAnimation` whenever it actually flips.
    private static func computeSlashMode(_ text: String) -> Bool {
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

    private func updateInputHeight(measuredContentHeight: CGFloat, animated: Bool) {
        measuredInputContentHeight = measuredContentHeight
        let nextHeight = MarkdownChatPillLayout.inputHeight(
            measuredContentHeight: measuredContentHeight,
            availableContentHeight: availableContentHeight
        )
        guard abs(nextHeight - inputHeight) > 0.5 else { return }

        if animated {
            withAnimation(Self.motion) {
                inputHeight = nextHeight
            }
        } else {
            inputHeight = nextHeight
        }
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
        isExpanded ? 18 : MarkdownChatPillLayout.collapsedHeight / 2
    }
    /// Pill height. Three states:
    ///   - collapsed (capsule strip): `collapsedHeight`
    ///   - expanded, no slash picker: `expandedHeight`
    ///   - expanded with slash picker open: + `skillsPickerSlotHeight`
    private var shellHeight: CGFloat {
        MarkdownChatPillLayout.shellHeight(
            isExpanded: isExpanded,
            pickerOpen: pickerOpen,
            inputHeight: inputHeight
        )
    }
    private var pickerOpen: Bool {
        isSlashMode && (matchingSkills?.isEmpty == false)
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
        // Picker now lives INSIDE pillShell (between input and divider)
        // to match the md-app.jsx mockup: one dark popover surface, not
        // a floating sibling that lets the markdown content bleed through
        // its translucent fill.
        pillShell
            .frame(maxWidth: MarkdownChatPillLayout.maxWidth)
            .overlayPreferenceValue(AgentButtonAnchorKey.self) { anchor in
                agentDropdownOverlay(anchor: anchor)
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

            // Animate the pill grow / shrink only when slash mode
            // actually toggles. Typing further characters inside slash
            // mode (e.g. /sh → /ship) just changes the filter, not the
            // picker's visibility, so we skip wrapping those in
            // withAnimation to avoid spurious re-layout transitions.
            let next = Self.computeSlashMode(newValue)
            if next != isSlashMode {
                withAnimation(Self.motion) {
                    isSlashMode = next
                }
            }
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
        .onChange(of: availableContentHeight) { _, _ in
            updateInputHeight(measuredContentHeight: measuredInputContentHeight, animated: true)
        }
        .onChange(of: shellHeight) { _, newHeight in
            onHeightChange?(newHeight)
        }
        .onAppear {
            updateInputHeight(measuredContentHeight: measuredInputContentHeight, animated: false)
            onHeightChange?(shellHeight)
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
                    .frame(height: MarkdownChatPillLayout.collapsedContentHeight, alignment: .center)

                inputArea
                    .frame(height: isExpanded ? inputHeight : 0, alignment: .topLeading)
                    .opacity(expandedOpacity)
                    .offset(y: isExpanded ? 0 : -4)
                    .clipped()
                    .allowsHitTesting(isExpanded)
                    .accessibilityHidden(!isExpanded)

                // Slash picker sits between input and divider, mirroring
                // md-app.jsx where SkillsMenu is the optional middle child
                // of the pill flex container. Pill height grows by
                // `skillsPickerSlotHeight` while it's visible.
                if isExpanded, isSlashMode, let skills = matchingSkills, !skills.isEmpty {
                    skillsPicker(skills)
                        .frame(maxHeight: MarkdownChatPillLayout.skillsPickerSlotHeight - 8, alignment: .top)
                }

                dividerSlot
                    .frame(height: isExpanded ? 5 : 0, alignment: .topLeading)
                    .opacity(expandedOpacity)
                    .clipped()

                footerRow
                    .frame(height: isExpanded ? MarkdownChatPillLayout.collapsedContentHeight : 0, alignment: .topLeading)
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
        // isSlashMode is mutated via `withAnimation(Self.motion)` in
        // `onChange(of: text)`, so we don't need an extra value-keyed
        // .animation modifier here — that would double-animate and
        // sometimes lose the transition timing on quick toggles.
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
        // Tracks `shellHeight`, which itself flexes between collapsed,
        // expanded, and expanded-with-slash-picker states. SwiftUI
        // animates the height transitions via `Self.motion` keyed on
        // `isExpanded` (and the picker-toggle drives a re-evaluation).
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
        // Picker fades in while the pill grows, and fades out while it
        // shrinks back. Both directions inherit `Self.motion` from the
        // outer `.animation(_:value: isSlashMode)` so the picker and the
        // pill height move in lockstep — no jarring pop-in, no late
        // fade-out after the height collapse.
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .top)),
            removal: .opacity
        ))
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
        measuredInputContentHeight = MarkdownChatPillLayout.baseInputHeight
        inputHeight = MarkdownChatPillLayout.baseInputHeight
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
        Group {
            if isExpanded {
                expandedHeaderRow
            } else {
                collapsedHeaderRow
            }
        }
    }

    private var expandedHeaderRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                contextChip(label: contextChipTitle)
                    .fixedSize(horizontal: true, vertical: false)
                autoModeLabel
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                contextChip(label: contextChipTitle)
                autoModeLabel
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var collapsedHeaderRow: some View {
        HStack(spacing: 10) {
            leadingChipSlot

            collapsedPromptLabel
                .layoutPriority(1)

            collapsedHeaderControls
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
        .frame(
            minWidth: 58,
            maxWidth: isExpanded ? Self.expandedChipMaxWidth : nil,
            alignment: .leading
        )
        .fixedSize(horizontal: !isExpanded, vertical: false)
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

    private var collapsedPromptLabel: some View {
        Text(collapsedPromptText)
            .font(.system(size: 13.5))
            .foregroundColor(MarkdownPillPalette.textDim)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(minWidth: 58, maxWidth: .infinity, alignment: .leading)
            .clipped()
    }

    private var autoModeLabel: some View {
        Text(String(localized: "markdownChat.pill.context.auto", defaultValue: "· auto"))
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(MarkdownPillPalette.textDim)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
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
                onContentHeightChange: { height in
                    updateInputHeight(measuredContentHeight: height, animated: true)
                },
                onReturn: { handleReturn() },
                onMoveUp: { handleMoveUp() },
                onMoveDown: { handleMoveDown() },
                onCancel: { handleCancel() }
            )
            .frame(maxWidth: .infinity, minHeight: inputHeight, maxHeight: inputHeight, alignment: .topLeading)

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
        // Publish the button's bounds so the body-level `.overlayPreferenceValue`
        // can render the dropdown ABOVE the pill, OUTSIDE the pill's clipShape
        // boundary (which would otherwise clip the popup).
        .anchorPreference(key: AgentButtonAnchorKey.self, value: .bounds) { $0 }
        .help(compact ? agent.label : "\(agent.label) (\(agent.shortcutHint))")
        .accessibilityLabel(Text(String(localized: "markdownChat.pill.agent.a11y", defaultValue: "Choose CLI agent")))
    }

    /// Renders the agent picker dropdown above the agent button. Anchored
    /// to the button's bounds via `AgentButtonAnchorKey`. Lives at the body
    /// level (outside the pillShell's clipShape) so the popup can extend
    /// above the pill without being clipped.
    @ViewBuilder
    private func agentDropdownOverlay(anchor: Anchor<CGRect>?) -> some View {
        GeometryReader { geo in
            if let anchor, agentMenuOpen {
                let rect = geo[anchor]
                let dropdownWidth: CGFloat = 220
                let gap: CGFloat = 6
                ZStack(alignment: .bottomLeading) {
                    Color.clear
                    agentDropdownPanel
                        .offset(x: max(0, min(geo.size.width - dropdownWidth, rect.midX - dropdownWidth / 2)))
                }
                .frame(
                    width: geo.size.width,
                    height: max(0, rect.minY - gap),
                    alignment: .bottomLeading
                )
                .allowsHitTesting(true)
            }
        }
        .dismissOnOutsideMouseUp(isPresented: $agentMenuOpen)
    }

    private var agentDropdownPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(MarkdownPillAgent.allCases) { option in
                Button {
                    agent = option
                    agentMenuOpen = false
                } label: {
                    MarkdownPillAgentMenuRow(
                        agent: option,
                        active: option == agent
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .frame(width: 220)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(MarkdownPillPalette.popoverBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(MarkdownPillPalette.borderStrong, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.55), radius: 30, x: 0, y: 24)
        .fixedSize(horizontal: false, vertical: true)
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
