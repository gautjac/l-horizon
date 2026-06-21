import XCTest
@testable import L_Horizon

/// Tests for the statutory-holiday calculator. Asserts against authoritative,
/// independently-known dates for 2026 (Easter 2026 = Sun Apr 5; Victoria Day /
/// National Patriots' Day 2026 = Mon May 18; Labour Day 2026 = Mon Sep 7;
/// Thanksgiving 2026 = Mon Oct 12).
final class HolidaysTests: XCTestCase {

    let cal = Calendar.horizon

    func ymd(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func dates(_ holidays: [Holiday]) -> Set<Date> { Set(holidays.map(\.date)) }

    // MARK: Québec

    func testQuebec2026FixedDays() {
        let d = dates(Holidays.quebec(year: 2026))
        XCTAssertTrue(d.contains(ymd(2026, 1, 1)))   // Jour de l'An
        XCTAssertTrue(d.contains(ymd(2026, 6, 24)))  // Fête nationale
        XCTAssertTrue(d.contains(ymd(2026, 7, 1)))   // Fête du Canada
        XCTAssertTrue(d.contains(ymd(2026, 12, 25))) // Noël
    }

    func testQuebec2026EasterRelative() {
        let d = dates(Holidays.quebec(year: 2026))
        XCTAssertTrue(d.contains(ymd(2026, 4, 3)))   // Vendredi saint (Easter − 2)
        XCTAssertTrue(d.contains(ymd(2026, 4, 6)))   // Lundi de Pâques (Easter + 1)
    }

    func testQuebec2026ComputedWeekdays() {
        let d = dates(Holidays.quebec(year: 2026))
        XCTAssertTrue(d.contains(ymd(2026, 5, 18)))  // Journée nationale des patriotes
        XCTAssertTrue(d.contains(ymd(2026, 9, 7)))   // Fête du Travail (1st Mon Sep)
        XCTAssertTrue(d.contains(ymd(2026, 10, 12))) // Action de grâce (2nd Mon Oct)
    }

    func testQuebecHasNineHolidays() {
        XCTAssertEqual(Holidays.quebec(year: 2026).count, 9)
    }

    func testQuebecDoesNotIncludeRemembranceOrBoxingDay() {
        let d = dates(Holidays.quebec(year: 2026))
        XCTAssertFalse(d.contains(ymd(2026, 11, 11))) // federal-only
        XCTAssertFalse(d.contains(ymd(2026, 12, 26))) // federal-only
    }

    // MARK: Canada (federal)

    func testCanada2026FederalDays() {
        let d = dates(Holidays.canada(year: 2026))
        XCTAssertTrue(d.contains(ymd(2026, 5, 18)))  // Victoria Day
        XCTAssertTrue(d.contains(ymd(2026, 9, 30)))  // Truth & Reconciliation
        XCTAssertTrue(d.contains(ymd(2026, 11, 11))) // Remembrance Day
        XCTAssertTrue(d.contains(ymd(2026, 12, 26))) // Boxing Day
    }

    func testCanadaDoesNotIncludeSaintJean() {
        XCTAssertFalse(dates(Holidays.canada(year: 2026)).contains(ymd(2026, 6, 24)))
    }

    // MARK: Easter algorithm spot-checks (known Gregorian Easter Sundays)

    func testEasterKnownYears() {
        // Good Friday = Easter − 2; assert via the Québec set.
        XCTAssertTrue(dates(Holidays.quebec(year: 2024)).contains(ymd(2024, 3, 29))) // Easter Sun Mar 31
        XCTAssertTrue(dates(Holidays.quebec(year: 2025)).contains(ymd(2025, 4, 18))) // Easter Sun Apr 20
        XCTAssertTrue(dates(Holidays.quebec(year: 2027)).contains(ymd(2027, 3, 26))) // Easter Sun Mar 28
    }

    // MARK: Region routing & ranges

    func testRegionNoneIsEmpty() {
        XCTAssertTrue(Holidays.list(.none, year: 2026).isEmpty)
    }

    func testMultiYearRangeAndMapAndSet() {
        let list = Holidays.list(.quebec, years: 2026...2027)
        XCTAssertEqual(list.count, 18)                          // 9 per year
        XCTAssertEqual(list, list.sorted { $0.date < $1.date }) // date-sorted
        XCTAssertNotNil(Holidays.map(.quebec, years: 2026...2026)[ymd(2026, 12, 25)])
        XCTAssertTrue(Holidays.dateSet(.quebec, years: 2026...2026).contains(ymd(2026, 7, 1)))
    }

    func testHolidayNameIsBilingual() {
        let noel = Holidays.quebec(year: 2026).first { $0.date == ymd(2026, 12, 25) }!
        XCTAssertEqual(noel.name(.fr), "Noël")
        XCTAssertEqual(noel.name(.en), "Christmas Day")
    }
}
