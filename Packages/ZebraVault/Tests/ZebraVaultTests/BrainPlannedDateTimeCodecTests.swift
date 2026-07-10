import XCTest
@testable import ZebraVault

final class BrainPlannedDateTimeCodecTests: XCTestCase {
    func testAcceptsRFC3339OffsetsAndZuluTime() {
        XCTAssertNotNil(BrainPlannedDateTimeCodec.date(fromStorageString: "2026-07-10T09:00:00+09:00"))
        XCTAssertNotNil(BrainPlannedDateTimeCodec.date(fromStorageString: "2026-07-10T00:00:00Z"))
        XCTAssertNotNil(BrainPlannedDateTimeCodec.date(fromStorageString: "2026-07-10T09:00:00.123+09:00"))
    }

    func testRejectsTimezoneLessAndReversedIntervals() {
        XCTAssertNil(BrainPlannedDateTimeCodec.date(fromStorageString: "2026-07-10T09:00:00"))
        XCTAssertNil(BrainPlannedDateTimeCodec.validatedInterval(
            startRaw: "2026-07-10T10:00:00+09:00",
            endRaw: "2026-07-10T09:00:00+09:00"
        ))
    }

    func testStorageStringRoundTripsWithExplicitLocalOffset() throws {
        let zone = try XCTUnwrap(TimeZone(secondsFromGMT: 9 * 3600))
        let date = try XCTUnwrap(BrainPlannedDateTimeCodec.date(fromStorageString: "2026-07-10T09:30:00+09:00"))

        let stored = BrainPlannedDateTimeCodec.storageString(from: date, timeZone: zone)

        XCTAssertEqual(stored, "2026-07-10T09:30:00+09:00")
        XCTAssertEqual(BrainPlannedDateTimeCodec.date(fromStorageString: stored), date)
    }
}
