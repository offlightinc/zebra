import XCTest
@testable import ZebraVault

final class VerticalTabsSidebarViewStatePersistenceTests: XCTestCase {
    @MainActor
    func testVaultSelectionDefaultsToHomeDirectoryWhenNothingStored() throws {
        let defaults = try makeDefaults()
        let home = try makeTemporaryDirectory(named: "home")
        try makeDirectory(named: "brain-offlight", in: home)
        try makeDirectory(named: "b-brain", in: home)

        let state = VerticalTabsSidebarVaultState(defaults: defaults, homeDirectoryPath: home.path)

        XCTAssertEqual(state.selectedVaultPath, home.path)
        XCTAssertEqual(state.vaults.map(\.path), [home.path])
    }

    @MainActor
    func testVaultSelectionRestoresStoredCustomVault() throws {
        let defaults = try makeDefaults()
        let home = try makeTemporaryDirectory(named: "home")
        let custom = try makeDirectory(named: "custom-vault", in: home)
        let brainOfflight = try makeDirectory(named: "brain-offlight", in: home)

        let firstState = VerticalTabsSidebarVaultState(defaults: defaults, homeDirectoryPath: home.path)
        firstState.addVault(url: custom)
        let restoredState = VerticalTabsSidebarVaultState(defaults: defaults, homeDirectoryPath: home.path)

        XCTAssertEqual(restoredState.selectedVaultPath, custom.path)
        XCTAssertTrue(restoredState.vaults.contains { $0.path == custom.path })
        XCTAssertFalse(restoredState.vaults.contains { $0.path == brainOfflight.path })
    }

    @MainActor
    func testVaultSelectionFallsBackToHomeWhenStoredVaultMissing() throws {
        let defaults = try makeDefaults()
        let home = try makeTemporaryDirectory(named: "home")
        let custom = try makeDirectory(named: "custom-vault", in: home)

        let firstState = VerticalTabsSidebarVaultState(defaults: defaults, homeDirectoryPath: home.path)
        firstState.addVault(url: custom)
        try FileManager.default.removeItem(at: custom)
        let restoredState = VerticalTabsSidebarVaultState(defaults: defaults, homeDirectoryPath: home.path)

        XCTAssertEqual(restoredState.selectedVaultPath, home.path)
        XCTAssertEqual(restoredState.vaults.map(\.path), [home.path])
    }

    @MainActor
    func testVaultSelectionRestoresBrainOfflightOnlyWhenUserSelectedIt() throws {
        let defaults = try makeDefaults()
        let home = try makeTemporaryDirectory(named: "home")
        let brainOfflight = try makeDirectory(named: "brain-offlight", in: home)

        let firstState = VerticalTabsSidebarVaultState(defaults: defaults, homeDirectoryPath: home.path)
        firstState.addVault(url: brainOfflight)
        let restoredState = VerticalTabsSidebarVaultState(defaults: defaults, homeDirectoryPath: home.path)

        XCTAssertEqual(restoredState.selectedVaultPath, brainOfflight.path)
        XCTAssertTrue(restoredState.vaults.contains { $0.path == brainOfflight.path })
    }

    func testTaskStateRoundTripsByRootPath() throws {
        let defaults = try makeDefaults()
        let root = "/tmp/zebra/tasks"
        let myFilter = TaskFilter(field: .owner, op: .is, values: ["여한우리", "홍남호"])
        let state = VerticalTabsSidebarViewStatePersistence.TaskState(
            groupBy: .owner,
            sort: .updated,
            sortDirection: .ascending,
            filters: [
                TaskFilter(field: .status, op: .is, values: ["todo"]),
                TaskFilter(field: .owner, op: .isNot, values: ["여한우리"]),
            ],
            collapsedSections: ["todo", "done"],
            myOwnerFilter: myFilter
        )

        VerticalTabsSidebarViewStatePersistence.saveTaskState(state, rootPath: root, defaults: defaults)
        let restored = VerticalTabsSidebarViewStatePersistence.loadTaskState(rootPath: root, defaults: defaults)

        XCTAssertEqual(restored.resolvedGroupBy, .owner)
        XCTAssertEqual(restored.resolvedSort, .updated)
        XCTAssertEqual(restored.resolvedSortDirection, .ascending)
        XCTAssertEqual(restored.resolvedFilters, state.resolvedFilters)
        XCTAssertEqual(Set(restored.collapsedSections), ["todo", "done"])
        XCTAssertEqual(restored.resolvedMyOwnerFilter, myFilter)
    }

    func testTaskStateNilMyOwnerFilterRoundTrips() throws {
        let defaults = try makeDefaults()
        let root = "/tmp/zebra/tasks-empty-my"
        let state = VerticalTabsSidebarViewStatePersistence.TaskState(
            groupBy: .status,
            filters: [],
            collapsedSections: [],
            myOwnerFilter: nil
        )

        VerticalTabsSidebarViewStatePersistence.saveTaskState(state, rootPath: root, defaults: defaults)
        let restored = VerticalTabsSidebarViewStatePersistence.loadTaskState(rootPath: root, defaults: defaults)

        XCTAssertNil(restored.resolvedMyOwnerFilter)
    }

    func testUnknownTaskSortFallsBackToTitle() throws {
        let state = VerticalTabsSidebarViewStatePersistence.TaskState(
            groupBy: TaskGroupBy.status.rawValue,
            sort: "future-sort",
            sortDirection: nil,
            filters: [],
            collapsedSections: [],
            myOwnerFilter: nil
        )

        XCTAssertEqual(state.resolvedSort, .title)
        XCTAssertEqual(state.resolvedSortDirection, .ascending)
    }

    func testUnknownTaskSortDirectionFallsBackToSortDefault() throws {
        let state = VerticalTabsSidebarViewStatePersistence.TaskState(
            groupBy: TaskGroupBy.status.rawValue,
            sort: TaskSort.updated.rawValue,
            sortDirection: "sideways",
            filters: [],
            collapsedSections: [],
            myOwnerFilter: nil
        )

        XCTAssertEqual(state.resolvedSort, .updated)
        XCTAssertEqual(state.resolvedSortDirection, .descending)
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

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZebraVaultTests-\(UUID().uuidString)", isDirectory: true)
        let directory = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return directory.standardizedFileURL
    }

    @discardableResult
    private func makeDirectory(named name: String, in parent: URL) throws -> URL {
        let directory = parent.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.standardizedFileURL
    }
}
