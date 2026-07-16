import CoreFoundation

enum SlackPollingWorkspaceRefreshSignal {
    static let name = CFNotificationName(
        "com.offlight.zebra.slack-polling-workspaces-changed" as CFString
    )

    static func post() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            name,
            nil,
            nil,
            true
        )
    }
}
