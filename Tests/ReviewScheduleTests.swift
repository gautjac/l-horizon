import XCTest
@testable import L_Horizon

/// Tests for the review-cadence scheduling math.
final class ReviewScheduleTests: XCTestCase {

    let cal = Calendar.horizon
    func ymd(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func testNextDuePerCadence() {
        let last = ymd(2026, 6, 1)
        XCTAssertEqual(ReviewSchedule.nextDue(lastReviewed: last, cadence: .weekly),   ymd(2026, 6, 8))
        XCTAssertEqual(ReviewSchedule.nextDue(lastReviewed: last, cadence: .monthly),  ymd(2026, 7, 1))
        XCTAssertEqual(ReviewSchedule.nextDue(lastReviewed: last, cadence: .seasonal), ymd(2026, 9, 1))
    }

    func testIsDueBoundary() {
        let last = ymd(2026, 6, 1)
        XCTAssertFalse(ReviewSchedule.isDue(lastReviewed: last, cadence: .weekly, now: ymd(2026, 6, 7)))
        XCTAssertTrue(ReviewSchedule.isDue(lastReviewed: last, cadence: .weekly, now: ymd(2026, 6, 8)))
        XCTAssertTrue(ReviewSchedule.isDue(lastReviewed: last, cadence: .weekly, now: ymd(2026, 6, 20)))
    }

    func testDaysUntilDueSignedForOverdue() {
        let last = ymd(2026, 6, 1)   // weekly → due Jun 8
        XCTAssertEqual(ReviewSchedule.daysUntilDue(lastReviewed: last, cadence: .weekly, now: ymd(2026, 6, 5)), 3)
        XCTAssertEqual(ReviewSchedule.daysUntilDue(lastReviewed: last, cadence: .weekly, now: ymd(2026, 6, 8)), 0)
        XCTAssertEqual(ReviewSchedule.daysUntilDue(lastReviewed: last, cadence: .weekly, now: ymd(2026, 6, 10)), -2)
    }
}
