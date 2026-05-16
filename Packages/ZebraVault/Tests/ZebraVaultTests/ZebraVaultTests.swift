import XCTest
@testable import ZebraVault

final class ZebraVaultScaffoldTests: XCTestCase {
    func testVersionStringIsScaffold() {
        XCTAssertEqual(ZebraVault.version, "0.0.0-scaffold")
    }
}
