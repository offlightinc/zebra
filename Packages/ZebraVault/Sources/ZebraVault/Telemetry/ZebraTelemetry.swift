import Foundation

public enum ZebraTelemetrySidebarArea: String, Sendable {
    case modeRail = "mode_rail"
    case row
    case toolbar
    case picker
    case statusButton = "status_button"
    case vaultButton = "vault_button"
    case gettingStarted = "getting_started"
    case terminalSurface = "terminal_surface"
}

public enum ZebraTelemetrySidebarSurface: String, Sendable {
    case task
    case goal
    case document
    case email
    case terminal
    case vault
    case onboarding
    case sync
    case unknown

    public init(mode: VerticalTabsSidebarMode) {
        switch mode {
        case .terminal:
            self = .terminal
        case .goals:
            self = .goal
        case .tasks:
            self = .task
        case .email:
            self = .email
        case .documents:
            self = .document
        }
    }
}

public enum ZebraTelemetrySidebarAction: String, Sendable {
    case click
    case select
    case toggle
    case filter
    case sort
    case group
    case structure
    case cadence
    case status
}

public enum ZebraTelemetryDocumentAction: String, Sendable {
    case create
    case update
    case delete
}

public enum ZebraTelemetryObjectType: String, Sendable {
    case task
    case goal
    case document
    case page
    case unknown
}

public enum ZebraTelemetryChangeOrigin: String, Sendable {
    case interactive
    case brainSync = "brain_sync"
    case sourceIngest = "source_ingest"
    case onboarding
    case unknown
}

public enum ZebraTelemetryChangeSource: String, Sendable {
    case vaultIndexDiff = "vault_index_diff"
    case markdownPanel = "markdown_panel"
    case sidebar
    case agentFlow = "agent_flow"
    case onboarding
}

public struct ZebraTelemetrySidebarInteractionEvent: Sendable {
    public let area: ZebraTelemetrySidebarArea
    public let surface: ZebraTelemetrySidebarSurface
    public let action: ZebraTelemetrySidebarAction
    public let itemID: String?
    public let value: String?

    public init(
        area: ZebraTelemetrySidebarArea,
        surface: ZebraTelemetrySidebarSurface,
        action: ZebraTelemetrySidebarAction,
        itemID: String? = nil,
        value: String? = nil
    ) {
        self.area = area
        self.surface = surface
        self.action = action
        self.itemID = itemID
        self.value = value
    }
}

public struct ZebraTelemetryChatPillPromptSubmittedEvent: Sendable {
    public let surface: String
    public let submitMethod: String
    public let agent: String?
    public let promptLength: Int

    public init(surface: String, submitMethod: String, agent: String?, promptLength: Int) {
        self.surface = surface
        self.submitMethod = submitMethod
        self.agent = agent
        self.promptLength = promptLength
    }
}

public struct ZebraTelemetryVaultDocumentChangedEvent: Sendable {
    public let action: ZebraTelemetryDocumentAction
    public let objectType: ZebraTelemetryObjectType
    public let changeOrigin: ZebraTelemetryChangeOrigin
    public let changeSource: ZebraTelemetryChangeSource
    public let path: String?

    public init(
        action: ZebraTelemetryDocumentAction,
        objectType: ZebraTelemetryObjectType,
        changeOrigin: ZebraTelemetryChangeOrigin,
        changeSource: ZebraTelemetryChangeSource,
        path: String?
    ) {
        self.action = action
        self.objectType = objectType
        self.changeOrigin = changeOrigin
        self.changeSource = changeSource
        self.path = path
    }
}

public struct ZebraTelemetryOnboardingStartClickedEvent: Sendable {
    public let source: String

    public init(source: String) {
        self.source = source
    }
}

public struct ZebraTelemetryOnboardingFileCreatedEvent: Sendable {
    public let objectType: ZebraTelemetryObjectType
    public let path: String?

    public init(objectType: ZebraTelemetryObjectType, path: String?) {
        self.objectType = objectType
        self.path = path
    }
}

public struct ZebraTelemetryChatPillToggledEvent: Sendable {
    public let expanded: Bool

    public init(expanded: Bool) {
        self.expanded = expanded
    }
}

public struct ZebraTelemetryInspectorToggledEvent: Sendable {
    public let visible: Bool

    public init(visible: Bool) {
        self.visible = visible
    }
}

@MainActor
public protocol ZebraTelemetrySink: AnyObject {
    func trackSidebarInteraction(_ event: ZebraTelemetrySidebarInteractionEvent)
    func trackChatPillPromptSubmitted(_ event: ZebraTelemetryChatPillPromptSubmittedEvent)
    func trackVaultDocumentChanged(_ event: ZebraTelemetryVaultDocumentChangedEvent)
    func trackOnboardingStartClicked(_ event: ZebraTelemetryOnboardingStartClickedEvent)
    func trackOnboardingFileCreated(_ event: ZebraTelemetryOnboardingFileCreatedEvent)
    func trackChatPillToggled(_ event: ZebraTelemetryChatPillToggledEvent)
    func trackInspectorToggled(_ event: ZebraTelemetryInspectorToggledEvent)
}

@MainActor
public enum ZebraTelemetry {
    public static weak var sink: ZebraTelemetrySink?

    public static func trackSidebarInteraction(
        area: ZebraTelemetrySidebarArea,
        surface: ZebraTelemetrySidebarSurface,
        action: ZebraTelemetrySidebarAction,
        itemID: String? = nil,
        value: String? = nil
    ) {
        sink?.trackSidebarInteraction(
            ZebraTelemetrySidebarInteractionEvent(
                area: area,
                surface: surface,
                action: action,
                itemID: itemID,
                value: value
            )
        )
    }

    public static func trackChatPillPromptSubmitted(
        surface: String,
        submitMethod: String,
        agent: String?,
        promptLength: Int
    ) {
        sink?.trackChatPillPromptSubmitted(
            ZebraTelemetryChatPillPromptSubmittedEvent(
                surface: surface,
                submitMethod: submitMethod,
                agent: agent,
                promptLength: promptLength
            )
        )
    }

    public static func trackVaultDocumentChanged(
        action: ZebraTelemetryDocumentAction,
        objectType: ZebraTelemetryObjectType,
        changeOrigin: ZebraTelemetryChangeOrigin,
        changeSource: ZebraTelemetryChangeSource,
        path: String?
    ) {
        sink?.trackVaultDocumentChanged(
            ZebraTelemetryVaultDocumentChangedEvent(
                action: action,
                objectType: objectType,
                changeOrigin: changeOrigin,
                changeSource: changeSource,
                path: path
            )
        )
    }

    public static func trackOnboardingStartClicked(source: String) {
        sink?.trackOnboardingStartClicked(ZebraTelemetryOnboardingStartClickedEvent(source: source))
    }

    public static func trackOnboardingFileCreated(
        objectType: ZebraTelemetryObjectType,
        path: String?
    ) {
        sink?.trackOnboardingFileCreated(
            ZebraTelemetryOnboardingFileCreatedEvent(objectType: objectType, path: path)
        )
    }

    public static func trackChatPillToggled(expanded: Bool) {
        sink?.trackChatPillToggled(ZebraTelemetryChatPillToggledEvent(expanded: expanded))
    }

    public static func trackInspectorToggled(visible: Bool) {
        sink?.trackInspectorToggled(ZebraTelemetryInspectorToggledEvent(visible: visible))
    }
}
