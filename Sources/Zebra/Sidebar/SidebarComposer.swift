import SwiftUI

/// Default slot views the cmux sidebar exposes to a composer. Each slot is a
/// fully-built, cmux-owned view — the composer decides where to place them.
///
/// This is the adapter contract the cmux sidebar promises. The default
/// composer (`SidebarComposer.cmuxDefault`) just stacks them; Zebra plugs in
/// a richer composer that wraps the slots with its own chrome.
struct SidebarSlots {
    /// The default cmux workspace list (workspaceScrollArea).
    let workspaceList: AnyView
    /// The default cmux footer (SidebarFooter with file-explorer button etc.).
    let defaultFooter: AnyView
    /// Forwarded onSendFeedback callback so a custom composer can wire its
    /// own footer to the same delegate the default footer would have used.
    let onSendFeedback: () -> Void
}

/// Adapter for the sidebar body layout. cmux calls `compose(slots)` once per
/// body re-render; the default composition is cmux's pre-Zebra layout.
struct SidebarComposer {
    let compose: (SidebarSlots) -> AnyView

    /// Cmux's original body — a simple ZStack of workspace list + footer.
    /// Selected via `EnvironmentValues.sidebarComposer`'s default when no
    /// override is injected, which is the safety net that lets cmux build
    /// and run without any Zebra wiring.
    static let cmuxDefault = SidebarComposer { slots in
        AnyView(
            ZStack(alignment: .bottomLeading) {
                slots.workspaceList
                slots.defaultFooter
            }
        )
    }
}

private struct SidebarComposerKey: EnvironmentKey {
    static let defaultValue: SidebarComposer = .cmuxDefault
}

extension EnvironmentValues {
    /// Override the sidebar body layout. Default = cmux's pre-Zebra ZStack.
    var sidebarComposer: SidebarComposer {
        get { self[SidebarComposerKey.self] }
        set { self[SidebarComposerKey.self] = newValue }
    }
}

private struct SidebarExtraLeadingInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// Extra leading inset for fullscreen window controls, contributed by the
    /// active sidebar composer. Default 0 (cmux ships with no extra inset);
    /// Zebra adds the mode rail width so the traffic lights clear the rail.
    var sidebarExtraLeadingInset: CGFloat {
        get { self[SidebarExtraLeadingInsetKey.self] }
        set { self[SidebarExtraLeadingInsetKey.self] = newValue }
    }
}
