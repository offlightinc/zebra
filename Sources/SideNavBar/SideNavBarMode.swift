import Foundation

enum SideNavBarMode: String, CaseIterable, Identifiable, Sendable {
    case goals
    case tasks
    case documents

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .goals: return "target"
        case .tasks: return "checklist"
        case .documents: return "doc.text"
        }
    }

    var label: String {
        switch self {
        case .goals:
            return String(localized: "sideNavBar.mode.goals", defaultValue: "Goals")
        case .tasks:
            return String(localized: "sideNavBar.mode.tasks", defaultValue: "Tasks")
        case .documents:
            return String(localized: "sideNavBar.mode.documents", defaultValue: "Documents")
        }
    }
}
