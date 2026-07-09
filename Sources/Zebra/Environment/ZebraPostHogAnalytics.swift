import AppKit
import CryptoKit
import Foundation
import PostHog
import Security
import ZebraVault

final class ZebraPostHogAnalytics {
    static let shared = ZebraPostHogAnalytics()

    private static let hashSaltDefaultsKey = "zebra.posthog.hashSalt.v1"
    private static let hashDomainSeparator = "zebra-posthog-v1"
    private static let hashSaltLock = NSLock()
    private static let projectTokenInfoDictionaryKey = "ZebraPostHogProjectToken"
    private static let projectTokenPlaceholder = "REPLACE_WITH_ZEBRA_POSTHOG_PROJECT_TOKEN"

    private let host = "https://us.i.posthog.com"

    private let dailyActiveEvent = "zebra_app_active_daily"
    private let hourlyActiveEvent = "zebra_app_active_hourly"

    private let lastActiveDayUTCKey = "zebra.posthog.lastActiveDayUTC"
    private let lastActiveHourUTCKey = "zebra.posthog.lastActiveHourUTC"

    private let workQueue: DispatchQueue
    private let workQueueSpecificKey = DispatchSpecificKey<Void>()
    private let utcHourFormatter: DateFormatter
    private let utcDayFormatter: DateFormatter

    private var didStart = false
    private var activeCheckTimer: Timer?

    private init() {
        workQueue = DispatchQueue(label: "com.offlight.zebra.posthog.analytics", qos: .utility)
        utcHourFormatter = Self.makeUTCFormatter("yyyy-MM-dd'T'HH")
        utcDayFormatter = Self.makeUTCFormatter("yyyy-MM-dd")
        workQueue.setSpecific(key: workQueueSpecificKey, value: ())
    }

    private var apiKey: String {
#if DEBUG
        return Self.postHogProjectToken(
            infoDictionary: Bundle.main.infoDictionary ?? [:],
            environment: ProcessInfo.processInfo.environment,
            allowEnvironmentOverride: true
        )
#else
        return Self.postHogProjectToken(
            infoDictionary: Bundle.main.infoDictionary ?? [:],
            environment: ProcessInfo.processInfo.environment,
            allowEnvironmentOverride: false
        )
#endif
    }

    private var isEnabled: Bool {
        guard TelemetrySettings.enabledForCurrentLaunch else { return false }
#if DEBUG
        return ProcessInfo.processInfo.environment["ZEBRA_POSTHOG_ENABLE"] == "1" && !apiKey.isEmpty
#else
        return !apiKey.isEmpty
#endif
    }

    func startIfNeeded() {
        dispatchAsyncOnWorkQueue { [weak self] in
            self?.startIfNeededOnWorkQueue()
        }
    }

    func trackAppActive(reason: String) {
        dispatchAsyncOnWorkQueue { [weak self] in
            guard let self else { return }

            let didCaptureDaily = self.trackDailyActiveOnWorkQueue(reason: reason, flush: false)
            let didCaptureHourly = self.trackHourlyActiveOnWorkQueue(reason: reason, flush: false)
            if didCaptureDaily || didCaptureHourly {
                PostHogSDK.shared.flush()
            }
        }
    }

    func trackChatPillPromptSubmitted(
        surface: String,
        submitMethod: String,
        agent: String?,
        promptLength: Int
    ) {
        capture(
            "zebra_chatpill_prompt_submitted",
            properties: Self.chatPillPromptSubmittedProperties(
                surface: surface,
                submitMethod: submitMethod,
                agent: agent,
                promptLength: promptLength,
                infoDictionary: Bundle.main.infoDictionary ?? [:]
            ),
            flush: true
        )
    }

    func trackVaultDocumentChanged(
        action: ZebraTelemetryDocumentAction,
        objectType: ZebraTelemetryObjectType,
        changeOrigin: ZebraTelemetryChangeOrigin,
        changeSource: ZebraTelemetryChangeSource,
        path: String?
    ) {
        capture(
            "zebra_vault_document_changed",
            properties: Self.vaultDocumentChangedProperties(
                action: action.rawValue,
                objectType: objectType.rawValue,
                changeOrigin: changeOrigin.rawValue,
                changeSource: changeSource.rawValue,
                path: path,
                infoDictionary: Bundle.main.infoDictionary ?? [:]
            ),
            flush: false
        )
    }

    func trackOnboardingStartClicked(source: String) {
        capture(
            "zebra_onboarding_start_clicked",
            properties: Self.onboardingStartClickedProperties(
                source: source,
                infoDictionary: Bundle.main.infoDictionary ?? [:]
            ),
            flush: true
        )
    }

    func trackOnboardingFileCreated(
        objectType: ZebraTelemetryObjectType,
        path: String?
    ) {
        capture(
            "zebra_onboarding_file_created",
            properties: Self.onboardingFileCreatedProperties(
                objectType: objectType.rawValue,
                path: path,
                infoDictionary: Bundle.main.infoDictionary ?? [:]
            ),
            flush: false
        )
    }

    func trackSidebarInteraction(
        area: ZebraTelemetrySidebarArea,
        surface: ZebraTelemetrySidebarSurface,
        action: ZebraTelemetrySidebarAction,
        itemID: String?,
        value: String?
    ) {
        capture(
            Self.sidebarInteractionEventName(area: area.rawValue, surface: surface.rawValue),
            properties: Self.sidebarInteractionProperties(
                area: area.rawValue,
                surface: surface.rawValue,
                action: action.rawValue,
                itemID: itemID,
                value: value,
                infoDictionary: Bundle.main.infoDictionary ?? [:]
            ),
            flush: false
        )
    }

    func trackChatPillToggled(expanded: Bool) {
        capture(
            "zebra_chatpill_toggled",
            properties: Self.chatPillToggledProperties(
                expanded: expanded,
                infoDictionary: Bundle.main.infoDictionary ?? [:]
            ),
            flush: false
        )
    }

    func trackInspectorToggled(visible: Bool) {
        capture(
            "zebra_inspector_toggled",
            properties: Self.inspectorToggledProperties(
                visible: visible,
                infoDictionary: Bundle.main.infoDictionary ?? [:]
            ),
            flush: false
        )
    }

    func flush() {
        dispatchSyncOnWorkQueue {
            guard didStart else { return }
            PostHogSDK.shared.flush()
        }
    }

    private func startIfNeededOnWorkQueue() {
        guard !didStart else { return }
        guard isEnabled else { return }

        let config = PostHogConfig(apiKey: apiKey, host: host)
        config.captureApplicationLifecycleEvents = false
        config.captureScreenViews = false
#if DEBUG
        config.debug = ProcessInfo.processInfo.environment["ZEBRA_POSTHOG_DEBUG"] == "1"
#endif

        PostHogSDK.shared.setup(config)
        PostHogSDK.shared.register(Self.superProperties(infoDictionary: Bundle.main.infoDictionary ?? [:]))

        didStart = true
        scheduleActiveCheckTimer()
    }

    private func scheduleActiveCheckTimer() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.activeCheckTimer?.invalidate()
            self.activeCheckTimer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
                guard let self else { return }
                guard NSApp.isActive else { return }
                self.trackAppActive(reason: "activeTimer")
            }
        }
    }

    private func capture(_ event: String, properties: [String: Any], flush: Bool) {
        dispatchAsyncOnWorkQueue { [weak self] in
            guard let self else { return }
            self.startIfNeededOnWorkQueue()
            guard self.didStart else { return }
            PostHogSDK.shared.capture(event, properties: properties)
            if flush || Self.shouldFlushAfterCapture(event: event) {
                PostHogSDK.shared.flush()
            }
        }
    }

    @discardableResult
    private func trackDailyActiveOnWorkQueue(reason: String, flush: Bool) -> Bool {
        startIfNeededOnWorkQueue()
        guard didStart else { return false }

        let today = utcDayString(Date())
        let defaults = UserDefaults.standard
        if defaults.string(forKey: lastActiveDayUTCKey) == today {
            return false
        }

        defaults.set(today, forKey: lastActiveDayUTCKey)

        let event = dailyActiveEvent
        PostHogSDK.shared.capture(
            event,
            properties: Self.dailyActiveProperties(
                dayUTC: today,
                reason: reason,
                infoDictionary: Bundle.main.infoDictionary ?? [:]
            )
        )

        if flush && Self.shouldFlushAfterCapture(event: event) {
            PostHogSDK.shared.flush()
        }

        return true
    }

    @discardableResult
    private func trackHourlyActiveOnWorkQueue(reason: String, flush: Bool) -> Bool {
        startIfNeededOnWorkQueue()
        guard didStart else { return false }

        let hour = utcHourString(Date())
        let defaults = UserDefaults.standard
        if defaults.string(forKey: lastActiveHourUTCKey) == hour {
            return false
        }

        defaults.set(hour, forKey: lastActiveHourUTCKey)

        let event = hourlyActiveEvent
        PostHogSDK.shared.capture(
            event,
            properties: Self.hourlyActiveProperties(
                hourUTC: hour,
                reason: reason,
                infoDictionary: Bundle.main.infoDictionary ?? [:]
            )
        )

        if flush && Self.shouldFlushAfterCapture(event: event) {
            PostHogSDK.shared.flush()
        }

        return true
    }

    private func dispatchAsyncOnWorkQueue(_ block: @escaping () -> Void) {
        if DispatchQueue.getSpecific(key: workQueueSpecificKey) != nil {
            block()
            return
        }
        workQueue.async(execute: block)
    }

    private func dispatchSyncOnWorkQueue(_ block: () -> Void) {
        if DispatchQueue.getSpecific(key: workQueueSpecificKey) != nil {
            block()
            return
        }
        workQueue.sync(execute: block)
    }

    private func utcHourString(_ date: Date) -> String {
        utcHourFormatter.string(from: date)
    }

    private func utcDayString(_ date: Date) -> String {
        utcDayFormatter.string(from: date)
    }

    private static func makeUTCFormatter(_ dateFormat: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = dateFormat
        return formatter
    }

    nonisolated static func superProperties(infoDictionary: [String: Any]) -> [String: Any] {
        var properties: [String: Any] = [
            "product": "zebra",
            "platform": "zebra_desktop",
        ]
        properties.merge(versionProperties(infoDictionary: infoDictionary)) { _, new in new }
        return properties
    }

    nonisolated static func dailyActiveProperties(
        dayUTC: String,
        reason: String,
        infoDictionary: [String: Any]
    ) -> [String: Any] {
        var properties: [String: Any] = [
            "day_utc": dayUTC,
            "reason": reason,
        ]
        properties.merge(versionProperties(infoDictionary: infoDictionary)) { _, new in new }
        return properties
    }

    nonisolated static func hourlyActiveProperties(
        hourUTC: String,
        reason: String,
        infoDictionary: [String: Any]
    ) -> [String: Any] {
        var properties: [String: Any] = [
            "hour_utc": hourUTC,
            "reason": reason,
        ]
        properties.merge(versionProperties(infoDictionary: infoDictionary)) { _, new in new }
        return properties
    }

    nonisolated static func sidebarInteractionProperties(
        area: String,
        surface: String,
        action: String,
        itemID: String?,
        value: String?,
        infoDictionary: [String: Any]
    ) -> [String: Any] {
        var properties = baseEventProperties(infoDictionary: infoDictionary)
        properties["sidebar_area"] = area
        properties["sidebar_mode"] = surface
        properties["interaction_type"] = sidebarInteractionType(area: area, surface: surface, action: action)
        if let controlName = sidebarControlName(area: area, surface: surface, action: action, value: value) {
            properties["control_name"] = controlName
        }
        if let itemID, !itemID.isEmpty {
            properties["item_id_hash"] = stableHash(itemID)
        }
        if let value, !value.isEmpty {
            properties["selected_value"] = value
        }
        return properties
    }

    nonisolated static func sidebarInteractionEventName(area: String, surface: String) -> String {
        switch area {
        case "mode_rail":
            return "zebra_sidebar_mode_interacted"
        case "row":
            return "zebra_sidebar_row_selected"
        case "picker":
            return "zebra_sidebar_picker_changed"
        case "toolbar":
            return "zebra_sidebar_toolbar_changed"
        case "status_button":
            return surface == "sync"
                ? "zebra_sidebar_sync_status_clicked"
                : "zebra_sidebar_item_status_changed"
        case "vault_button":
            return "zebra_sidebar_vault_clicked"
        case "getting_started":
            return "zebra_sidebar_onboarding_toggled"
        case "terminal_surface":
            return "zebra_sidebar_terminal_surface_interacted"
        default:
            return "zebra_sidebar_other_interacted"
        }
    }

    nonisolated private static func sidebarInteractionType(
        area: String,
        surface: String,
        action: String
    ) -> String {
        switch area {
        case "picker", "toolbar":
            return "change"
        case "status_button":
            return surface == "sync" ? "click" : "change"
        default:
            return action
        }
    }

    nonisolated private static func sidebarControlName(
        area: String,
        surface: String,
        action: String,
        value: String?
    ) -> String? {
        switch area {
        case "picker":
            return action
        case "toolbar":
            return action == "group" ? "group_by" : action
        case "status_button":
            return surface == "sync" ? "sync_status" : "status"
        case "vault_button":
            if action == "select" { return "vault" }
            if value == "choose_folder" { return "manage_vaults" }
            return action
        case "getting_started":
            return "onboarding_visibility"
        default:
            return nil
        }
    }

    nonisolated static func chatPillPromptSubmittedProperties(
        surface: String,
        submitMethod: String,
        agent: String?,
        promptLength: Int,
        infoDictionary: [String: Any]
    ) -> [String: Any] {
        var properties = baseEventProperties(infoDictionary: infoDictionary)
        properties["surface"] = surface
        properties["submit_method"] = submitMethod
        properties["prompt_length_bucket"] = promptLengthBucket(promptLength)
        if let agent, !agent.isEmpty {
            properties["agent"] = agent
        }
        return properties
    }

    nonisolated static func vaultDocumentChangedProperties(
        action: String,
        objectType: String,
        changeOrigin: String,
        changeSource: String,
        path: String?,
        infoDictionary: [String: Any]
    ) -> [String: Any] {
        var properties = baseEventProperties(infoDictionary: infoDictionary)
        properties["action"] = action
        properties["object_type"] = objectType
        properties["change_origin"] = changeOrigin
        properties["change_source"] = changeSource
        if let path, !path.isEmpty {
            properties["path_hash"] = stableHash(path)
        }
        return properties
    }

    nonisolated static func onboardingStartClickedProperties(
        source: String,
        infoDictionary: [String: Any]
    ) -> [String: Any] {
        var properties = baseEventProperties(infoDictionary: infoDictionary)
        properties["source"] = source
        return properties
    }

    nonisolated static func onboardingFileCreatedProperties(
        objectType: String,
        path: String?,
        infoDictionary: [String: Any]
    ) -> [String: Any] {
        var properties = baseEventProperties(infoDictionary: infoDictionary)
        properties["object_type"] = objectType
        if let path, !path.isEmpty {
            properties["path_hash"] = stableHash(path)
        }
        return properties
    }

    nonisolated static func chatPillToggledProperties(
        expanded: Bool,
        infoDictionary: [String: Any]
    ) -> [String: Any] {
        var properties = baseEventProperties(infoDictionary: infoDictionary)
        properties["action"] = expanded ? "expand" : "collapse"
        return properties
    }

    nonisolated static func inspectorToggledProperties(
        visible: Bool,
        infoDictionary: [String: Any]
    ) -> [String: Any] {
        var properties = baseEventProperties(infoDictionary: infoDictionary)
        properties["action"] = visible ? "show" : "hide"
        return properties
    }

    nonisolated static func shouldFlushAfterCapture(event: String) -> Bool {
        switch event {
        case "zebra_app_active_daily", "zebra_app_active_hourly",
             "zebra_chatpill_prompt_submitted", "zebra_onboarding_start_clicked":
            return true
        default:
            return false
        }
    }

    nonisolated static func postHogProjectToken(
        infoDictionary: [String: Any],
        environment: [String: String] = [:],
        allowEnvironmentOverride: Bool = false
    ) -> String {
        if allowEnvironmentOverride,
           let envToken = normalizedPostHogProjectToken(environment["ZEBRA_POSTHOG_API_KEY"]) {
            return envToken
        }

        return normalizedPostHogProjectToken(infoDictionary[projectTokenInfoDictionaryKey]) ?? ""
    }

    nonisolated private static func normalizedPostHogProjectToken(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed != projectTokenPlaceholder else { return nil }
        return trimmed
    }

    nonisolated static func promptLengthBucket(_ length: Int) -> String {
        switch max(0, length) {
        case 0:
            return "0"
        case 1...20:
            return "1_20"
        case 21...100:
            return "21_100"
        case 101...500:
            return "101_500"
        default:
            return "501_plus"
        }
    }

    nonisolated static func stableHash(_ value: String) -> String {
        stableHash(value, salt: telemetryHashSalt())
    }

    nonisolated static func stableHash(_ value: String, salt: Data) -> String {
        var data = Data()
        data.append(Data(hashDomainSeparator.utf8))
        data.append(0 as UInt8)
        data.append(salt)
        data.append(0 as UInt8)
        data.append(Data(value.utf8))
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    nonisolated private static func telemetryHashSalt(defaults: UserDefaults = .standard) -> Data {
        hashSaltLock.lock()
        defer { hashSaltLock.unlock() }

        if let encoded = defaults.string(forKey: hashSaltDefaultsKey),
           let data = Data(base64Encoded: encoded),
           data.count == 32 {
            return data
        }

        var bytes = [UInt8](repeating: 0, count: 32)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }

        let data: Data
        if status == errSecSuccess {
            data = Data(bytes)
        } else {
            let fallback = "\(UUID().uuidString):\(UUID().uuidString):\(Date().timeIntervalSince1970)"
            data = Data(SHA256.hash(data: Data(fallback.utf8)))
        }

        defaults.set(data.base64EncodedString(), forKey: hashSaltDefaultsKey)
        return data
    }

#if DEBUG
    nonisolated static func clearTelemetryHashSaltForTesting(defaults: UserDefaults = .standard) {
        hashSaltLock.lock()
        defer { hashSaltLock.unlock() }
        defaults.removeObject(forKey: hashSaltDefaultsKey)
    }
#endif

    nonisolated private static func baseEventProperties(infoDictionary: [String: Any]) -> [String: Any] {
        versionProperties(infoDictionary: infoDictionary)
    }

    nonisolated private static func versionProperties(infoDictionary: [String: Any]) -> [String: Any] {
        var properties: [String: Any] = [:]
        if let value = infoDictionary["CFBundleShortVersionString"] as? String, !value.isEmpty {
            properties["app_version"] = value
        }
        if let value = infoDictionary["CFBundleVersion"] as? String, !value.isEmpty {
            properties["app_build"] = value
        }
        return properties
    }
}

@MainActor
final class ZebraTelemetryPostHogBridge: ZebraTelemetrySink {
    static let shared = ZebraTelemetryPostHogBridge()

    private init() {}

    func trackSidebarInteraction(_ event: ZebraTelemetrySidebarInteractionEvent) {
        ZebraPostHogAnalytics.shared.trackSidebarInteraction(
            area: event.area,
            surface: event.surface,
            action: event.action,
            itemID: event.itemID,
            value: event.value
        )
    }

    func trackChatPillPromptSubmitted(_ event: ZebraTelemetryChatPillPromptSubmittedEvent) {
        ZebraPostHogAnalytics.shared.trackChatPillPromptSubmitted(
            surface: event.surface,
            submitMethod: event.submitMethod,
            agent: event.agent,
            promptLength: event.promptLength
        )
    }

    func trackVaultDocumentChanged(_ event: ZebraTelemetryVaultDocumentChangedEvent) {
        ZebraPostHogAnalytics.shared.trackVaultDocumentChanged(
            action: event.action,
            objectType: event.objectType,
            changeOrigin: event.changeOrigin,
            changeSource: event.changeSource,
            path: event.path
        )
    }

    func trackOnboardingStartClicked(_ event: ZebraTelemetryOnboardingStartClickedEvent) {
        ZebraPostHogAnalytics.shared.trackOnboardingStartClicked(source: event.source)
    }

    func trackOnboardingFileCreated(_ event: ZebraTelemetryOnboardingFileCreatedEvent) {
        ZebraPostHogAnalytics.shared.trackOnboardingFileCreated(
            objectType: event.objectType,
            path: event.path
        )
    }

    func trackChatPillToggled(_ event: ZebraTelemetryChatPillToggledEvent) {
        ZebraPostHogAnalytics.shared.trackChatPillToggled(expanded: event.expanded)
    }

    func trackInspectorToggled(_ event: ZebraTelemetryInspectorToggledEvent) {
        ZebraPostHogAnalytics.shared.trackInspectorToggled(visible: event.visible)
    }
}
