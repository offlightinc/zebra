import SwiftUI

/// Conflict 케이스에서 tooltip 안에 표시되는 agent picker chip + dropdown.
///
/// 디자인 spec (`/Users/han/zebra_design/zebra_sync/`):
/// - chip: pill (border-radius 999), padding 3 7 3 5, bg `BVColor.bg`,
///   border `BVColor.accent`, font 10.5px weight 500
/// - dropdown (`.ag-list`): width 170, padding 4, gap 1, bg `#0c0c0c`
/// - 3 rows: codex (⌥1) / claude (⌥2) / gemini (⌥3)
///
/// Selection 은 `UserDefaults` 의 `zebra.brainSync.preferredAgent` 에 persist.
/// chip click 시 dropdown toggle. dropdown 의 row click 시 onSelect callback +
/// preference 저장 + dropdown close.
///
/// Tap gesture 가 tooltip 외부 onTapGesture (= sync retry) 를 가리도록 chip
/// 자체를 Button 으로. SwiftUI 의 nested Button 은 외부 gesture 보다 우선.
struct BrainSyncAgentPicker: View {
    @Binding var preferredAgent: MarkdownPillAgent
    var onSelect: (MarkdownPillAgent) -> Void

    @State private var open = false
    @State private var dropdownHeight: CGFloat = 120

    var body: some View {
        // 가로 layout — "click to resolve with [◇ codex ▾]" 형태.
        // text 부분을 별도 Button 으로 만들어서 click 시 default agent 로 terminal.
        // chip 도 자기 Button — SwiftUI 가 hit-test 영역별로 분리해서 두 click
        // 동작이 섞이지 않는다. text click = onSelect(preferred), chip click =
        // dropdown toggle.
        HStack(spacing: 8) {
            Button(action: { onSelect(preferredAgent) }) {
                Text(String(localized: "brainSync.hint.resolveWith", defaultValue: "click to resolve with"))
                    .font(.system(size: 10.5))
                    .foregroundColor(BVColor.fgFaint)
            }
            .buttonStyle(.plain)
            chipButton
        }
        .padding(.top, 6)
        .frame(maxWidth: .infinity, alignment: .center)
        // dropdown 은 chip **위쪽** 으로 떠야 함 (디자인 spec: bottom: calc(100% + 5px)).
        // .topTrailing anchor + GeometryReader 로 dropdown 자체 height 측정해서
        // 그 만큼 위로 offset (안전망 = approx 120pt). alignmentGuide 는 SwiftUI
        // 의 vertical height 계산을 깨는 케이스가 있어 회피.
        .overlay(alignment: .topTrailing) {
            if open {
                dropdown
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .preference(key: BrainSyncDropdownHeightKey.self, value: proxy.size.height)
                        }
                    )
                    .offset(y: -(dropdownHeight + 5))
            }
        }
        .onPreferenceChange(BrainSyncDropdownHeightKey.self) { newValue in
            // GeometryReader 가 0 으로 시작 후 한 frame 후 실제 height 보고.
            // approx 120pt fallback 만 깔고 한 frame 더 보정.
            if newValue > 0 { dropdownHeight = newValue }
        }
        .dismissOnOutsideMouseUp(isPresented: $open)
    }

    private var chipButton: some View {
        Button(action: { open.toggle() }) {
            HStack(spacing: 5) {
                MarkdownPillAgentDot(agent: preferredAgent, size: 12)
                Text(preferredAgent.label)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(BVColor.fg)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundColor(BVColor.fgFaint)
                    .rotationEffect(.degrees(open ? 180 : 0))
                    .animation(.easeOut(duration: 0.15), value: open)
            }
            .padding(.leading, 5)
            .padding(.trailing, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(BVColor.bg)
                    .overlay(
                        Capsule().stroke(BVColor.accent, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var dropdown: some View {
        VStack(spacing: 1) {
            ForEach(MarkdownPillAgent.allCases) { agent in
                row(for: agent)
            }
        }
        .padding(4)
        .frame(width: 170, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: NSColor(srgbRed: 0x0c / 255.0, green: 0x0c / 255.0, blue: 0x0c / 255.0, alpha: 1.0)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 6)
        .transition(.opacity.combined(with: .offset(y: 4)))
    }

    private func row(for agent: MarkdownPillAgent) -> some View {
        Button(action: { select(agent) }) {
            HStack(spacing: 7) {
                MarkdownPillAgentDot(agent: agent, size: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(agent.label)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(BVColor.fg)
                    Text(vendorLabel(for: agent))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.42))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(shortcutHint(for: agent))
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.45))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color(nsColor: NSColor(srgbRed: 0x18 / 255.0, green: 0x18 / 255.0, blue: 0x18 / 255.0, alpha: 1.0)))
                            .overlay(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                            )
                    )
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(BrainSyncAgentRowButtonStyle())
    }

    private func select(_ agent: MarkdownPillAgent) {
        preferredAgent = agent
        open = false
        onSelect(agent)
    }

    private func vendorLabel(for agent: MarkdownPillAgent) -> String {
        switch agent {
        case .codex: return "OpenAI"
        case .claude: return "Anthropic"
        case .gemini: return "Google"
        }
    }

    private func shortcutHint(for agent: MarkdownPillAgent) -> String {
        switch agent {
        case .codex: return "⌥1"
        case .claude: return "⌥2"
        case .gemini: return "⌥3"
        }
    }
}

private struct BrainSyncAgentRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(configuration.isPressed ? Color.white.opacity(0.08) : Color.clear)
            )
            .onHover { isHover in
                // SwiftUI ButtonStyle 안에서는 직접 hover 처리 어려움 — 별도
                // wrapper 가 필요하면 그때 처리. V1 에선 pressed-only feedback.
                _ = isHover
            }
    }
}

/// GeometryReader 로 측정한 dropdown 의 height 를 부모 view 로 전달하는 PreferenceKey.
/// `BrainSyncAgentPicker` 가 그 값으로 offset(y: -(h+5)) 계산해 chip 위쪽으로 띄움.
private struct BrainSyncDropdownHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// `UserDefaults` 의 preferred agent slug 를 typed `MarkdownPillAgent` 로 read/write.
/// chip 의 default 표시 + 신규 선택 persist 에 사용.
enum BrainSyncAgentPreference {
    private static let key = "zebra.brainSync.preferredAgent"

    static var current: MarkdownPillAgent {
        get {
            if let raw = UserDefaults.standard.string(forKey: key),
               let agent = MarkdownPillAgent(rawValue: raw) {
                return agent
            }
            return .codex
        }
    }

    static func set(_ agent: MarkdownPillAgent) {
        UserDefaults.standard.set(agent.rawValue, forKey: key)
    }
}
