import XCTest
@testable import ZebraVault

final class VerticalTabsSidebarViewStatePersistenceTests: XCTestCase {
    func testTaskStateRoundTripsByRootPath() throws {
        let defaults = try makeDefaults()
        let root = "/tmp/zebra/tasks"
        let state = VerticalTabsSidebarViewStatePersistence.TaskState(
            groupBy: .owner,
            filters: [
                TaskFilter(field: .status, op: .is, values: ["todo"]),
                TaskFilter(field: .owner, op: .isNot, values: ["여한우리"]),
            ],
            collapsedSections: ["todo", "done"]
        )

        VerticalTabsSidebarViewStatePersistence.saveTaskState(state, rootPath: root, defaults: defaults)
        let restored = VerticalTabsSidebarViewStatePersistence.loadTaskState(rootPath: root, defaults: defaults)

        XCTAssertEqual(restored.resolvedGroupBy, .owner)
        XCTAssertEqual(restored.resolvedFilters, state.resolvedFilters)
        XCTAssertEqual(Set(restored.collapsedSections), ["todo", "done"])
    }

    func testDocumentStateIsScopedByRootPath() throws {
        let defaults = try makeDefaults()
        VerticalTabsSidebarViewStatePersistence.saveDocumentState(
            .init(collapsedFolders: ["agent-infra/", "companies/"]),
            rootPath: "/tmp/zebra-a",
            defaults: defaults
        )

        let restoredA = VerticalTabsSidebarViewStatePersistence.loadDocumentState(
            rootPath: "/tmp/zebra-a",
            defaults: defaults
        )
        let restoredB = VerticalTabsSidebarViewStatePersistence.loadDocumentState(
            rootPath: "/tmp/zebra-b",
            defaults: defaults
        )

        XCTAssertEqual(restoredA.collapsedFolders, ["agent-infra/", "companies/"])
        XCTAssertEqual(restoredB.collapsedFolders, [])
    }

    private func makeDefaults() throws -> UserDefaults {
        let name = "VerticalTabsSidebarViewStatePersistenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
