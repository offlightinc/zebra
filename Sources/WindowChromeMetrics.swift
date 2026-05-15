import CoreGraphics

enum WindowChromeMetrics {
    static let sharedChromeBarHeight: CGFloat = 28
    static let appTitlebarHeight: CGFloat = sharedChromeBarHeight
    static let bonsplitTabBarHeight: CGFloat = sharedChromeBarHeight
    static let secondaryTitlebarHeight: CGFloat = sharedChromeBarHeight
    static let minimumTitlebarHeight: CGFloat = sharedChromeBarHeight
    static let maximumTitlebarHeight: CGFloat = 72
    static let defaultTitlebarHeight: CGFloat = sharedChromeBarHeight

    static func clampedTitlebarHeight(_ height: CGFloat) -> CGFloat {
        max(minimumTitlebarHeight, min(maximumTitlebarHeight, height))
    }
}

enum MinimalModeChromeMetrics {
    static let titlebarHeight: CGFloat = WindowChromeMetrics.appTitlebarHeight
}

enum RightSidebarChromeMetrics {
    static let titlebarHeight: CGFloat = WindowChromeMetrics.appTitlebarHeight
    static let secondaryBarHeight: CGFloat = WindowChromeMetrics.secondaryTitlebarHeight
    static let barHorizontalPadding: CGFloat = 8
    static let barVerticalPadding: CGFloat = 3
    static let controlHeight: CGFloat = secondaryBarHeight - (barVerticalPadding * 2)
    static let controlHorizontalPadding: CGFloat = 8
    static let controlCornerRadius: CGFloat = 5
}

enum SidebarWorkspaceListMetrics {
    static let firstRowTopOffset: CGFloat = MinimalModeChromeMetrics.titlebarHeight + 2
    static let rowVerticalPadding: CGFloat = 8
    static let topScrimHeight: CGFloat = firstRowTopOffset + 20
    static let bottomScrimHeight: CGFloat = topScrimHeight

    /// 두 번째 줄 외곽 height. Tasks (TaskListToolbar) 와 Goals (GoalsPicker)
    /// 가 같은 값을 써서, 모드 전환 시 그 아래 첫 section header (Task "진행 중"
    /// / Goal "활성") 위치가 일치하도록 강제. Goal picker 의 segment 배경 inset
    /// (.padding(2)) 때문에 dynamic 만으로는 4pt 차이가 생긴다.
    static let secondRowHeight: CGFloat = 36

    static var scrollTopInset: CGFloat {
        max(0, firstRowTopOffset - rowVerticalPadding)
    }
}

struct SidebarWorkspaceScrollInsets: Equatable {
    static let workspaceList = SidebarWorkspaceScrollInsets(
        top: SidebarWorkspaceListMetrics.scrollTopInset,
        bottom: SidebarWorkspaceListMetrics.bottomScrimHeight
    )

    let top: CGFloat
    let bottom: CGFloat

    nonisolated var total: CGFloat {
        top + bottom
    }
}

enum SidebarWorkspaceScrollLayout {
    nonisolated static func contentMinHeight(
        viewportHeight: CGFloat,
        insets: SidebarWorkspaceScrollInsets
    ) -> CGFloat {
        max(0, viewportHeight - insets.total)
    }
}
