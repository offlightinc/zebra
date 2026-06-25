import Foundation

/// Zebra product defaults that intentionally diverge from upstream cmux.
enum ZebraAppearanceDefaults {
    struct LaunchSeed {
        fileprivate let shouldReapplyAfterSettingsBootstrap: Bool
    }

    private static let defaultMode: AppearanceMode = .dark

    static func prepareLaunchSeed(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) -> LaunchSeed {
        let shouldReapply =
            defaults.object(forKey: AppearanceSettings.appearanceModeKey) == nil &&
            !settingsFileExists(fileManager: fileManager)

        seedIfNeeded(defaults: defaults)
        return LaunchSeed(shouldReapplyAfterSettingsBootstrap: shouldReapply)
    }

    static func seedIfNeeded(defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: AppearanceSettings.appearanceModeKey) == nil else {
            return
        }

        defaults.set(defaultMode.rawValue, forKey: AppearanceSettings.appearanceModeKey)
    }

    static func finishLaunchSeed(_ seed: LaunchSeed, defaults: UserDefaults = .standard) {
        guard seed.shouldReapplyAfterSettingsBootstrap else { return }
        defaults.set(defaultMode.rawValue, forKey: AppearanceSettings.appearanceModeKey)
    }

    private static func settingsFileExists(fileManager: FileManager) -> Bool {
        [
            CmuxSettingsFileStore.defaultPrimaryPath,
            CmuxSettingsFileStore.defaultFallbackPath,
            CmuxSettingsFileStore.defaultApplicationSupportFallbackPath,
        ]
        .compactMap { $0 }
        .contains { fileManager.fileExists(atPath: $0) }
    }
}
