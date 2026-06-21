import XCTest
@testable import L_Horizon

/// Tests for the pure calendar layout, milestone placement, and working-day
/// counting that backs the calendar workspace.
final class CalendarPlanTests: XCTestCase {

    let cal = Calendar.horizon

    func ymd(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    // MARK: Month enumeration

    func testMonthsInclusiveRange() {
        let months = CalendarPlan.months(from: ymd(2026, 1, 15), to: ymd(2026, 4, 2))
        XCTAssertEqual(months, [ymd(2026, 1, 1), ymd(2026, 2, 1), ymd(2026, 3, 1), ymd(2026, 4, 1)])
    }

    func testMonthsSpanningYearBoundary() {
        let months = CalendarPlan.months(from: ymd(2026, 11, 20), to: ymd(2027, 1, 5))
        XCTAssertEqual(months, [ymd(2026, 11, 1), ymd(2026, 12, 1), ymd(2027, 1, 1)])
    }

    // MARK: Week layout (Monday-first)

    func testWeeksAreMondayFirstAndFullRows() {
        // January 2026: Jan 1 is a Thursday, so the first grid cell is Mon Dec 29.
        let weeks = CalendarPlan.weeks(of: ymd(2026, 1, 1))
        XCTAssertTrue(weeks.allSatisfy { $0.count == 7 })
        XCTAssertEqual(weeks.first?.first, ymd(2025, 12, 29))           // leading filler Monday
        XCTAssertEqual(cal.component(.weekday, from: weeks.first!.first!), 2) // Monday
        XCTAssertTrue(weeks.flatMap { $0 }.contains(ymd(2026, 1, 1)))   // the month's first day appears
    }

    func testWeeksCoverEveryDayOfMonthExactlyOnce() {
        let weeks = CalendarPlan.weeks(of: ymd(2026, 2, 1)) // 28 days, non-leap
        let inFeb = weeks.flatMap { $0 }.filter { CalendarPlan.isSameMonth($0, ymd(2026, 2, 1)) }
        XCTAssertEqual(Set(inFeb).count, 28)
    }

    // MARK: Weekend detection

    func testWeekendDetection() {
        XCTAssertTrue(CalendarPlan.isWeekend(ymd(2026, 6, 20)))  // Saturday
        XCTAssertTrue(CalendarPlan.isWeekend(ymd(2026, 6, 21)))  // Sunday
        XCTAssertFalse(CalendarPlan.isWeekend(ymd(2026, 6, 22))) // Monday
    }

    // MARK: Effective milestone date

    func testEffectiveDateUsesExplicitTarget() {
        let anchor = ymd(2026, 1, 1)
        let target = ymd(2026, 3, 17)
        XCTAssertEqual(
            CalendarPlan.effectiveDate(targetDate: target, horizon: .oneYear, anchor: anchor),
            target)
    }

    func testEffectiveDateFallsBackToHorizonWindowEnd() {
        let anchor = ymd(2026, 1, 1)
        XCTAssertEqual(
            CalendarPlan.effectiveDate(targetDate: nil, horizon: .threeMonths, anchor: anchor),
            ymd(2026, 4, 1)) // 3 months after the anchor
    }

    // MARK: Working-day counting

    func testWorkingDaysExcludesWeekendsAlways() {
        // Mon Jun 1 → Fri Jun 5 2026 inclusive of end, exclusive of start = 4 weekdays.
        let n = CalendarPlan.workingDays(from: ymd(2026, 6, 1), to: ymd(2026, 6, 5),
                                         holidays: [], excludeHolidays: false)
        XCTAssertEqual(n, 4)
    }

    func testWorkingDaysSkipsWeekendInSpan() {
        // Fri Jun 19 → Mon Jun 22 2026: Sat & Sun excluded, only Mon counts = 1.
        let n = CalendarPlan.workingDays(from: ymd(2026, 6, 19), to: ymd(2026, 6, 22),
                                         holidays: [], excludeHolidays: false)
        XCTAssertEqual(n, 1)
    }

    func testHolidayToggleChangesCount() {
        // Tue Jun 23 → Thu Jun 25 2026, with Jun 24 (Saint-Jean) a holiday.
        let holidays: Set<Date> = [ymd(2026, 6, 24)]
        let with = CalendarPlan.workingDays(from: ymd(2026, 6, 23), to: ymd(2026, 6, 25),
                                            holidays: holidays, excludeHolidays: true)
        let without = CalendarPlan.workingDays(from: ymd(2026, 6, 23), to: ymd(2026, 6, 25),
                                               holidays: holidays, excludeHolidays: false)
        XCTAssertEqual(with, 1)    // Jun 24 dropped, only Jun 25 counts
        XCTAssertEqual(without, 2) // Jun 24 + Jun 25
    }

    func testWorkingDaysZeroWhenEndNotAfterStart() {
        XCTAssertEqual(CalendarPlan.workingDays(from: ymd(2026, 6, 10), to: ymd(2026, 6, 10),
                                                holidays: [], excludeHolidays: false), 0)
        XCTAssertEqual(CalendarPlan.workingDays(from: ymd(2026, 6, 10), to: ymd(2026, 6, 1),
                                                holidays: [], excludeHolidays: false), 0)
    }
}
