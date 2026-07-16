import XCTest
@testable import ZebraVault

final class ZebraChatPillPanePlacementSettingsTests: XCTestCase {
    func testMissingAndInvalidValuesResolveToBelow() {
        XCTAssertEqual(ZebraChatPillPanePlacementSettings.placement(for: nil), .below)
        XCTAssertEqual(ZebraChatPillPanePlacementSettings.placement(for: "diagonal"), .below)
    }

    func testStoredRightValueResolvesToRight() throws {
        let suiteName = "ZebraChatPillPanePlacementSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(ZebraChatPillPanePlacement.right.rawValue, forKey: ZebraChatPillPanePlacementSettings.key)

        XCTAssertEqual(
            ZebraChatPillPanePlacementSettings.resolvedPlacement(defaults: defaults),
            .right
        )
    }
}
