import XCTest
@testable import L_Horizon

/// Tests for the pure horizon/date math, cascade ordering, and the re-flow
/// planner — the load-bearing logic of L'Horizon.
final class HorizonTests: XCTestCase {

    let cal = Calendar.horizon
    var anchor: Date!

    override func setUp() {
        super.setUp()
        // A fixed anchor so every windowed assertion is deterministic.
        anchor = cal.date(from: DateComponents(year: 2026, month: 1, day: 1))!
    }

    func date(monthsFromAnchor m: Int, days d: Int = 0) -> Date {
        let withMonths = cal.date(byAdding: .month, value: m, to: anchor)!
        return cal.date(byAdding: .day, value: d, to: withMonths)!
    }

    // MARK: Horizon windows & containment

    func testCascadeOrderAndMonths() {
        XCTAssertEqual(Horizon.cascade, [.threeMonths, .sixMonths, .oneYear, .threeYears, .fiveYears])
        XCTAssertEqual(Horizon.cascade.map(\.months), [3, 6, 12, 36, 60])
    }

    func testComparableByWindow() {
        XCTAssertTrue(Horizon.threeMonths < Horizon.sixMonths)
        XCTAssertTrue(Horizon.oneYear < Horizon.fiveYears)
        XCTAssertFalse(Horizon.threeYears < Horizon.oneYear)
    }

    func testWindowEndDates() {
        XCTAssertEqual(Horizon.threeMonths.windowEnd(from: anchor), date(monthsFromAnchor: 3))
        XCTAssertEqual(Horizon.oneYear.windowEnd(from: anchor), date(monthsFromAnchor: 12))
        XCTAssertEqual(Horizon.fiveYears.windowEnd(from: anchor), date(monthsFromAnchor: 60))
    }

    func testWindowStartIsPreviousHorizonEnd() {
        // Nearest horizon starts at the anchor.
        XCTAssertEqual(Horizon.threeMonths.windowStart(from: anchor), anchor)
        // 6mo window starts where 3mo ends.
        XCTAssertEqual(Horizon.sixMonths.windowStart(from: anchor), date(monthsFromAnchor: 3))
        // 5yr window starts where 3yr ends.
        XCTAssertEqual(Horizon.fiveYears.windowStart(from: anchor), date(monthsFromAnchor: 36))
    }

    func testContainingClassifiesEachWindow() {
        // Inside the first window.
        XCTAssertEqual(Horizon.containing(date(monthsFromAnchor: 1), anchor: anchor), .threeMonths)
        // Exactly at a window edge → that horizon (inclusive of its end).
        XCTAssertEqual(Horizon.containing(date(monthsFromAnchor: 3), anchor: anchor), .threeMonths)
        // Just past 3mo → 6mo.
        XCTAssertEqual(Horizon.containing(date(monthsFromAnchor: 3, days: 1), anchor: anchor), .sixMonths)
        // Between 6mo and 1yr → 1yr.
        XCTAssertEqual(Horizon.containing(date(monthsFromAnchor: 9), anchor: anchor), .oneYear)
        // Between 1yr and 3yr → 3yr.
        XCTAssertEqual(Horizon.containing(date(monthsFromAnchor: 24), anchor: anchor), .threeYears)
        // Between 3yr and 5yr → 5yr.
        XCTAssertEqual(Horizon.containing(date(monthsFromAnchor: 48), anchor: anchor), .fiveYears)
    }

    func testContainingClampsPastAndFuture() {
        // A date before the anchor falls in the nearest horizon.
        XCTAssertEqual(Horizon.containing(date(monthsFromAnchor: -2), anchor: anchor), .threeMonths)
        // Beyond five years clamps to the summit.
        XCTAssertEqual(Horizon.containing(date(monthsFromAnchor: 120), anchor: anchor), .fiveYears)
    }

    func testShorterAndLongerNeighbours() {
        XCTAssertNil(Horizon.threeMonths.shorter)
        XCTAssertEqual(Horizon.threeMonths.longer, .sixMonths)
        XCTAssertEqual(Horizon.oneYear.shorter, .sixMonths)
        XCTAssertEqual(Horizon.oneYear.longer, .threeYears)
        XCTAssertNil(Horizon.fiveYears.longer)
        XCTAssertEqual(Horizon.fiveYears.shorter, .threeYears)
    }

    // MARK: Cascade ordering

    func testCascadeOrderedNearToFar() {
        let items = [
            PlanItem(id: UUID(), title: "far", horizon: .fiveYears, status: .planned, progress: 0),
            PlanItem(id: UUID(), title: "near", horizon: .threeMonths, status: .active, progress: 0.5),
            PlanItem(id: UUID(), title: "mid", horizon: .oneYear, status: .planned, progress: 0.2),
        ]
        let ordered = Cascade.ordered(items)
        XCTAssertEqual(ordered.map(\.title), ["near", "mid", "far"])
    }

    func testCascadeTieBrokenByProgressDescending() {
        let a = PlanItem(id: UUID(), title: "low", horizon: .threeMonths, status: .active, progress: 0.2)
        let b = PlanItem(id: UUID(), title: "high", horizon: .threeMonths, status: .active, progress: 0.9)
        let ordered = Cascade.ordered([a, b])
        XCTAssertEqual(ordered.map(\.title), ["high", "low"])
    }

    func testLanesAlwaysReturnFiveInCascadeOrder() {
        let lanes = Cascade.lanes([
            PlanItem(id: UUID(), title: "x", horizon: .oneYear, status: .planned, progress: 0)
        ])
        XCTAssertEqual(lanes.map(\.0), Horizon.cascade)
        XCTAssertEqual(lanes.first(where: { $0.0 == .oneYear })?.1.count, 1)
        XCTAssertEqual(lanes.first(where: { $0.0 == .threeMonths })?.1.count, 0)
    }

    func testNearTermAnchorWellFormedness() {
        let onlyFar = [PlanItem(id: UUID(), title: "f", horizon: .fiveYears, status: .planned, progress: 0)]
        XCTAssertFalse(Cascade.hasNearTermAnchor(onlyFar))

        let withNear = onlyFar + [PlanItem(id: UUID(), title: "n", horizon: .threeMonths, status: .active, progress: 0)]
        XCTAssertTrue(Cascade.hasNearTermAnchor(withNear))

        // No far items at all → trivially well-formed.
        XCTAssertTrue(Cascade.hasNearTermAnchor([]))
    }

    // MARK: Re-flow planner

    func testReflowLeavesDoneUntouched() {
        let item = PlanItem(id: UUID(), title: "done", horizon: .oneYear, status: .done, progress: 1)
        let changes = Reflow.plan(items: [item], anchor: anchor, now: date(monthsFromAnchor: 2))
        XCTAssertEqual(changes.count, 1)
        XCTAssertTrue(changes[0].isNoOp)
        XCTAssertEqual(changes[0].toStatus, .done)
    }

    func testReflowSlippedAtNearestPushesToNextHorizonAndReplans() {
        let item = PlanItem(id: UUID(), title: "slip", horizon: .threeMonths, status: .slipped, progress: 0)
        let changes = Reflow.plan(items: [item], anchor: anchor, now: date(monthsFromAnchor: 4))
        XCTAssertEqual(changes[0].toHorizon, .sixMonths)
        XCTAssertEqual(changes[0].toStatus, .planned)
        XCTAssertTrue(changes[0].movedHorizon)
    }

    func testReflowSlippedFurtherOutActivatesInPlace() {
        let item = PlanItem(id: UUID(), title: "slip", horizon: .oneYear, status: .slipped, progress: 0.3)
        let changes = Reflow.plan(items: [item], anchor: anchor, now: date(monthsFromAnchor: 8))
        XCTAssertEqual(changes[0].toHorizon, .oneYear)        // stays
        XCTAssertEqual(changes[0].toStatus, .active)          // committed
        XCTAssertFalse(changes[0].movedHorizon)
        XCTAssertTrue(changes[0].changedStatus)
    }

    func testReflowMissedTargetMarksSlipped() {
        let id = UUID()
        let item = PlanItem(id: id, title: "late", horizon: .oneYear, status: .planned, progress: 0.4)
        let targets = [id: date(monthsFromAnchor: 5)]
        // now is past the target.
        let changes = Reflow.plan(items: [item], anchor: anchor, now: date(monthsFromAnchor: 7),
                                  targetDates: targets)
        XCTAssertEqual(changes[0].toStatus, .slipped)
        XCTAssertTrue(changes[0].changedStatus)
    }

    func testReflowDoesNotSlipACompletedItemPastTarget() {
        let id = UUID()
        let item = PlanItem(id: id, title: "fine", horizon: .oneYear, status: .planned, progress: 1.0)
        let targets = [id: date(monthsFromAnchor: 5)]
        let changes = Reflow.plan(items: [item], anchor: anchor, now: date(monthsFromAnchor: 7),
                                  targetDates: targets)
        XCTAssertNotEqual(changes[0].toStatus, .slipped)
    }

    func testReflowActivatesPlannedNearestLane() {
        let item = PlanItem(id: UUID(), title: "soon", horizon: .threeMonths, status: .planned, progress: 0)
        let changes = Reflow.plan(items: [item], anchor: anchor, now: date(monthsFromAnchor: 1))
        XCTAssertEqual(changes[0].toStatus, .active)
    }

    func testRationaleIsBilingual() {
        let k = RationaleKind.slippedPushed(.sixMonths)
        XCTAssertTrue(k.text(.fr).contains("6 mois") || k.text(.fr).contains("6"))
        XCTAssertNotEqual(k.text(.fr), k.text(.en))
        XCTAssertEqual(RationaleKind.onTrack.text(.en), "On track.")
        XCTAssertEqual(RationaleKind.onTrack.text(.fr), "Sur la bonne voie.")
    }

    func testTallyCountsAdvancedSlippedMoved() {
        let changes = [
            ReflowChange(id: UUID(), title: "a", fromHorizon: .threeMonths, toHorizon: .threeMonths,
                         fromStatus: .planned, toStatus: .active, kind: .nearActivated),
            ReflowChange(id: UUID(), title: "b", fromHorizon: .threeMonths, toHorizon: .sixMonths,
                         fromStatus: .slipped, toStatus: .planned, kind: .slippedPushed(.sixMonths)),
            ReflowChange(id: UUID(), title: "c", fromHorizon: .oneYear, toHorizon: .oneYear,
                         fromStatus: .planned, toStatus: .slipped, kind: .missedTarget),
        ]
        let t = Reflow.tally(changes)
        XCTAssertEqual(t.advanced, 1)   // a: planned→active
        XCTAssertEqual(t.slipped, 1)    // c: →slipped
        XCTAssertEqual(t.moved, 1)      // b moved horizon
    }
}
