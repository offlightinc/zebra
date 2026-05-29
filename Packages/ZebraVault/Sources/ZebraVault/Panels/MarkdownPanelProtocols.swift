import Bonsplit
import Combine
import Foundation

// Protocol seam between cmux's concrete `MarkdownPanel` / `Workspace` /
// `TerminalPanel` and ZebraVault's markdown-panel view. Conformances live
// on the cmux side under `Sources/Zebra/Adapters/MarkdownPanel+ZebraVault.swift`
// so this package never has to name the cmux model types.

@MainActor
public protocol ZebraMarkdownPanelModel: ObservableObject {
    var id: UUID { get }
    var filePath: String { get }
    var displayTitle: String { get }
    var content: String { get }
    var isFileUnavailable: Bool { get }
    /// Bumped each time cmux asks the panel to flash its focus ring.
    /// Drives a SwiftUI `.onChange` in `ZebraMarkdownPanelView`.
    var focusFlashToken: Int { get }
    /// brain-offlight 컨벤션에 맞춰 task/goal status 전이를 한 묶음으로 처리
    /// (status/updated/completed 필드 + body Timeline append).
    /// `newStatusRaw == nil` 이면 status 키 자체를 비움 + Timeline 에 비우기
    /// 기록. 상세는 `BrainStatusMutator.applyStatusChange`.
    func applyStatusChange(
        kind: BrainStatusMutator.Kind,
        oldStatusRaw: String?,
        newStatusRaw: String?
    )
    /// 일반 property (priority/owner/reviewer/due/target_date/review_cadence 등)
    /// 변경. `<field>:` 갱신 + `updated:` bump + body Timeline append 를 한
    /// 묶음으로 처리. status 는 별도 의미론이 있으므로 `applyStatusChange` 사용.
    func applyPropertyChange(
        field: String,
        oldValue: String?,
        newValue: String?
    )
}

@MainActor
public protocol ZebraTerminalPanel: AnyObject {
    var id: UUID { get }
    func sendInput(_ text: String)
    /// True once the underlying ghostty surface pointer is non-nil.
    var isSurfaceReady: Bool { get }
}

@MainActor
public protocol ZebraMarkdownWorkspace: AnyObject, ObservableObject {
    var id: UUID { get }
    var allPaneIds: [PaneID] { get }

    func paneWidth(forPane paneId: PaneID) -> Double?

    func ensurePaneWidth(_ minimumWidth: Double, forPane paneId: PaneID) -> Bool

    func openOrFocusMarkdownSurface(
        inPane paneId: PaneID,
        filePath: String,
        focus: Bool
    ) -> (any ZebraMarkdownPanelModel)?

    func newTerminalSurface(
        inPane paneId: PaneID,
        focus: Bool?,
        initialCommand: String?
    ) -> (any ZebraTerminalPanel)?

    func newTerminalSplit(
        from panelId: UUID,
        orientation: SplitOrientation,
        initialCommand: String?
    ) -> (any ZebraTerminalPanel)?

    func reusableAgentCompanionPane(forContentPane paneId: PaneID) -> PaneID?

    func paneId(forPanelId panelId: UUID) -> PaneID?
}
