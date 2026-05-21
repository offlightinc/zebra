import XCTest
@testable import ZebraVault

final class BrainDateOnlyCodecTests: XCTestCase {
    func testPickerDateSerializesSelectedLocalDayAcrossUTCBoundary() {
        var seoulCalendar = Calendar(identifier: .gregorian)
        seoulCalendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!

        let selected = seoulCalendar.date(from: DateComponents(year: 2026, month: 5, day: 22))!

        XCTAssertEqual(
            BrainDateOnlyCodec.storageString(fromPickerDate: selected, calendar: seoulCalendar),
            "2026-05-22"
        )
    }

    func testParsedStorageDateSerializesUTCStorageDay() {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let parsed = utcCalendar.date(from: DateComponents(year: 2026, month: 5, day: 22))!

        XCTAssertEqual(
            BrainDateOnlyCodec.storageString(fromParsedDate: parsed),
            "2026-05-22"
        )
    }

    func testStorageDateParsesAsLocalCalendarDayInNegativeTimezone() {
        var losAngelesCalendar = Calendar(identifier: .gregorian)
        losAngelesCalendar.timeZone = TimeZone(secondsFromGMT: -7 * 3600)!

        let parsed = BrainDateOnlyCodec.date(
            fromStorageString: "2026-05-22",
            calendar: losAngelesCalendar
        )!

        XCTAssertEqual(
            BrainDateOnlyCodec.storageString(fromPickerDate: parsed, calendar: losAngelesCalendar),
            "2026-05-22"
        )
    }

    func testSelectedNextDayProducesPropertyChangeInPositiveTimezone() {
        var seoulCalendar = Calendar(identifier: .gregorian)
        seoulCalendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!

        let selected = seoulCalendar.date(from: DateComponents(year: 2026, month: 5, day: 22))!
        let outcome = BrainStatusMutator.applyPropertyChange(
            in: """
            ---
            type: task
            due: 2026-05-21
            ---
            """,
            field: "due",
            oldValue: "2026-05-21",
            newValue: BrainDateOnlyCodec.storageString(fromPickerDate: selected, calendar: seoulCalendar),
            today: selected
        )

        XCTAssertTrue(outcome.didChange)
        XCTAssertTrue(outcome.newSource.contains("due: 2026-05-22"))
    }
}
