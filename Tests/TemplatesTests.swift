import XCTest
@testable import L_Horizon

/// Well-formedness of the starter-template catalogue.
final class TemplatesTests: XCTestCase {

    func testCatalogueNotEmptyAndLookup() {
        XCTAssertFalse(Templates.all.isEmpty)
        for t in Templates.all {
            XCTAssertEqual(Templates.byID(t.id)?.id, t.id)
        }
        XCTAssertNil(Templates.byID("does-not-exist"))
    }

    func testEachTemplateIsWellFormed() {
        for t in Templates.all {
            XCTAssertFalse(t.titleFR.isEmpty); XCTAssertFalse(t.titleEN.isEmpty)
            XCTAssertFalse(t.detailFR.isEmpty); XCTAssertFalse(t.detailEN.isEmpty)
            XCTAssertFalse(t.milestones.isEmpty, "\(t.id) has no milestones")
            // Every template must plant a concrete first step in the nearest horizon.
            XCTAssertTrue(t.milestones.contains { $0.horizon == .threeMonths },
                          "\(t.id) has no 3-month milestone")
            for m in t.milestones {
                XCTAssertFalse(m.titleFR.isEmpty); XCTAssertFalse(m.titleEN.isEmpty)
                XCTAssertFalse(m.dodFR.isEmpty); XCTAssertFalse(m.dodEN.isEmpty)
                XCTAssertFalse(m.stepsFR.isEmpty, "\(t.id)/\(m.titleEN) has no FR steps")
                XCTAssertEqual(m.stepsFR.count, m.stepsEN.count,
                               "\(t.id)/\(m.titleEN) FR/EN step count mismatch")
                XCTAssertTrue(Horizon.cascade.contains(m.horizon))
                // Milestones shouldn't reach past the template's summit horizon.
                XCTAssertLessThanOrEqual(m.horizon, t.topHorizon)
            }
        }
    }

    func testBilingualAccessors() {
        let t = Templates.documentary
        XCTAssertEqual(t.title(.fr), t.titleFR)
        XCTAssertEqual(t.title(.en), t.titleEN)
        XCTAssertEqual(t.milestoneCount, t.milestones.count)
    }
}
