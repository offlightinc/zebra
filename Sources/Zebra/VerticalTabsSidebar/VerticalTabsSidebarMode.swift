import Foundation

enum VerticalTabsSidebarMode: String, CaseIterable, Identifiable, Sendable {
    case terminal
    case goals
    case tasks
    case email
    case documents

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .terminal: return "terminal"
        case .goals: return "flag"
        case .tasks: return "checklist"
        case .email: return "envelope"
        case .documents: return "doc.text"
        }
    }

    var label: String {
        switch self {
        case .terminal:
            return String(localized: "verticalTabsSidebar.mode.terminal", defaultValue: "Terminal")
        case .goals:
            return String(localized: "verticalTabsSidebar.mode.goals", defaultValue: "Goals")
        case .tasks:
            return String(localized: "verticalTabsSidebar.mode.tasks", defaultValue: "Tasks")
        case .email:
            return String(localized: "verticalTabsSidebar.mode.email", defaultValue: "Email")
        case .documents:
            return String(localized: "verticalTabsSidebar.mode.documents", defaultValue: "Documents")
        }
    }
}
