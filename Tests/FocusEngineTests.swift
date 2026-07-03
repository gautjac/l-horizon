import XCTest
@testable import L_Horizon

/// Tests for the "Maintenant" focus selection & ordering.
final class FocusEngineTests: XCTestCase {

    let cal = Calendar.horizon
    let now = Calendar.horizon.date(from: DateComponents(year: 2026, month: 6, day: 1))!

    func cand(_ h: Horizon, _ s: MilestoneStatus, daysOut: Int) -> FocusCandidate {
        FocusCandidate(id: UUID(), horizon: h, status: s,
                       effectiveDate: cal.date(byAdding: .day, value: daysOut, to: now)!, openSteps: 0)
    }

    func testExcludesDone() {
        let items = FocusEngine.select([cand(.threeMonths, .done, daysOut: 5)], now: now)
        XCTAssertTrue(items.isEmpty)
    }

    func testReasonAssignment() {
        let slip = cand(.oneYear, .slipped, daysOut: 100)   // slipped regardless of date
        let act  = cand(.oneYear, .active, daysOut: 100)
        let soon = cand(.oneYear, .planned, daysOut: 10)    // within 21-day window
        let near = cand(.threeMonths, .planned, daysOut: 200) // nearest horizon, far date
        let far  = cand(.oneYear, .planned, daysOut: 200)   // nothing → excluded

        let items = FocusEngine.select([far, near, soon, act, slip], now: now)
        let byReason = Dictionary(uniqueKeysWithValues: items.map { ($0.reason, $0.id) })
        XCTAssertEqual(items.count, 4)
        XCTAssertEqual(byReason[.slipped], slip.id)
        XCTAssertEqual(byReason[.active], act.id)
        XCTAssertEqual(byReason[.dueSoon], soon.id)
        XCTAssertEqual(byReason[.nearHorizon], near.id)
        XCTAssertNil(items.first { $0.id == far.id })
    }

    func testOrderingByReasonThenDate() {
        let slip = cand(.oneYear, .slipped, daysOut: 50)
        let act  = cand(.oneYear, .active, daysOut: 5)
        let soonEarly = cand(.sixMonths, .planned, daysOut: 3)
        let soonLate  = cand(.sixMonths, .planned, daysOut: 15)
        let items = FocusEngine.select([soonLate, act, soonEarly, slip], now: now)
        // slipped → active → dueSoon(earlier) → dueSoon(later)
        XCTAssertEqual(items.map(\.id), [slip.id, act.id, soonEarly.id, soonLate.id])
    }
}
