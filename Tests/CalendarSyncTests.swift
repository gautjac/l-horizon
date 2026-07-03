import XCTest
@testable import L_Horizon

/// Tests for the pure event-mapping used by the Calendar sync (no EventKit).
final class CalendarSyncTests: XCTestCase {

    func testDraftTitleIsMarked() {
        let d = CalendarSync.draft(title: "Lock the treatment", dod: "", intentionTitle: "Film",
                                   horizon: .threeMonths, lang: .en)
        XCTAssertEqual(d.title, "◇ Lock the treatment")
    }

    func testDraftNotesIncludeIntentionAndHorizon() {
        let d = CalendarSync.draft(title: "X", dod: "", intentionTitle: "Patrick Norman",
                                   horizon: .oneYear, lang: .fr)
        XCTAssertTrue(d.notes.contains("Patrick Norman"))
        XCTAssertTrue(d.notes.contains("1 an"))
    }

    func testDraftNotesIncludeDefinitionOfDoneWhenPresent() {
        let fr = CalendarSync.draft(title: "X", dod: "Document validé", intentionTitle: "F",
                                    horizon: .sixMonths, lang: .fr)
        XCTAssertTrue(fr.notes.contains("Fait quand : Document validé"))
        let en = CalendarSync.draft(title: "X", dod: "Signed off", intentionTitle: "F",
                                    horizon: .sixMonths, lang: .en)
        XCTAssertTrue(en.notes.contains("Done when: Signed off"))
    }

    func testDraftOmitsDoneWhenEmpty() {
        let d = CalendarSync.draft(title: "X", dod: "", intentionTitle: "F",
                                   horizon: .sixMonths, lang: .en)
        XCTAssertFalse(d.notes.contains("Done when"))
    }
}
