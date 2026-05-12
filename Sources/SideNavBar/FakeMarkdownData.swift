import Foundation

struct FakeMarkdownEntry: Identifiable, Hashable {
    let path: String
    let displayName: String
    let relativeParent: String
    let content: String
    var id: String { path }
}

enum FakeMarkdownData {
    static let entries: [FakeMarkdownEntry] = [
        FakeMarkdownEntry(
            path: "ARCHITECTURE.md",
            displayName: "ARCHITECTURE.md",
            relativeParent: "",
            content: """
            # Architecture

            cmux is a **SwiftUI + AppKit hybrid** macOS app. The root `ContentView` is large and hosts the entire workspace layout.

            ## Key components

            | Component | Purpose |
            |-----------|---------|
            | Workspace sidebar | tab list |
            | Right sidebar | files / find / sessions |
            | Main area | terminal / browser / preview |
            | SNB (new) | left navigator |

            ## Ghostty integration

            Ghostty is vendored as a submodule and built into `GhosttyKit.xcframework`.
            """
        ),
        FakeMarkdownEntry(
            path: "NOTES.md",
            displayName: "NOTES.md",
            relativeParent: "",
            content: """
            # Notes

            Random working notes.

            > Resizers are tied to ContentView's private state. To add SNB resizer we extended `SidebarResizerHandle` enum.

            ## Open questions

            - Should SNB content panel be visible by default?
            - How does workspace switch interact with currently-selected file?
            - Multi-window state sharing?
            """
        ),
        FakeMarkdownEntry(
            path: "README.md",
            displayName: "README.md",
            relativeParent: "",
            content: """
            # offlight Workspace

            Internal docs for the **offlight** product workspace.

            ## Quick start

            ```bash
            bun install
            bun dev
            ```

            ## What's next

            - [ ] Land the navigator prototype
            - [ ] Decide on B / C / D layout
            - [ ] Wire real workspace cwd
            """
        ),
        FakeMarkdownEntry(
            path: "TODO.md",
            displayName: "TODO.md",
            relativeParent: "",
            content: """
            # TODO

            This week:

            1. Ship SNB Phase 0 prototypes
            2. Review with Dan
            3. Pick a layout option
            4. Wire real data in M2

            ## Backlog

            - Search across markdown files
            - Authoring (edit + create)
            - Per-mode content (goals vs tasks vs documents)
            """
        ),
        FakeMarkdownEntry(
            path: "docs/install.md",
            displayName: "install.md",
            relativeParent: "docs/",
            content: """
            # Install

            Requirements: macOS 14+, Xcode 15+, Zig 0.15.2.

            ```bash
            ./scripts/setup.sh
            ./scripts/reload.sh --tag dev --launch
            ```

            On macOS 26, set `CMUX_SKIP_ZIG_BUILD=1` to skip the ghostty CLI helper build.
            """
        ),
        FakeMarkdownEntry(
            path: "docs/setup.md",
            displayName: "setup.md",
            relativeParent: "docs/",
            content: """
            # Setup

            One-time bootstrap for the offlight fork.

            1. Clone the repo
            2. Initialize submodules
            3. Run `./scripts/setup.sh`
            4. Open Xcode and build the `cmux` scheme

            > Tip: tagged debug builds avoid clashing with the main cmux instance.
            """
        ),
    ]

    static func entry(for path: String) -> FakeMarkdownEntry? {
        entries.first { $0.path == path }
    }
}
