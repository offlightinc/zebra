import CoreGraphics

/// Zebra-specific sidebar geometry. Lives next to the Zebra sidebar code
/// instead of in cmux's `WindowChromeMetrics` so layout tweaks for the
/// mode rail / Tasks / Goals views don't leak into cmux files.
enum ZebraSidebarMetrics {
    /// 두 번째 줄 외곽 height. Tasks (TaskListToolbar) 와 Goals (GoalsPicker)
    /// 가 같은 값을 써서, 모드 전환 시 그 아래 첫 section header (Task "진행 중"
    /// / Goal "활성") 위치가 일치하도록 강제. Goal picker 의 segment 배경 inset
    /// (.padding(2)) 때문에 dynamic 만으로는 4pt 차이가 생긴다.
    static let secondRowHeight: CGFloat = 36
}
