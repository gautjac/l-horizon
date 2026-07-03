import Foundation
import SwiftData

/// Lifecycle status of a milestone. Drives the rings and the re-flow planner.
enum MilestoneStatus: String, Codable, CaseIterable, Identifiable {
    case planned    // not started
    case active     // in progress
    case done       // achieved
    case slipped    // missed its window in a review; awaiting re-flow

    var id: String { rawValue }

    func label(_ lang: Lang) -> String {
        switch self {
        case .planned: return lang == .fr ? "à venir"   : "planned"
        case .active:  return lang == .fr ? "en cours"   : "active"
        case .done:    return lang == .fr ? "fait"       : "done"
        case .slipped: return lang == .fr ? "glissé"     : "slipped"
        }
    }
}

/// A top-level intention — typically a long-horizon aim (the 5-year), which owns
/// a tree of milestones cascading down to the nearest horizon.
@Model
final class Intention {
    var id: UUID = UUID()
    var title: String = ""
    var detail: String = ""               // optional context / the "why"
    /// The anchor all horizon windows are measured from. Set at creation; the
    /// review ritual can re-anchor to "today" when re-flowing.
    var anchorDate: Date = Date()
    /// The top horizon this intention reaches for (default five years).
    var topHorizonRaw: Int = Horizon.fiveYears.rawValue
    var createdAt: Date = Date()
    var sortIndex: Int = 0
    /// How often this intention wants a review ritual — drives the "due" banner
    /// and the local review reminders.
    var reviewCadenceRaw: String = ReviewCadence.weekly.rawValue
    /// When on, milestone target dates are mirrored into the system Calendar.
    var calendarSyncEnabled: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \Milestone.intention)
    var milestones: [Milestone]? = []

    @Relationship(deleteRule: .cascade, inverse: \ReviewLog.intention)
    var reviews: [ReviewLog]? = []

    init(title: String, detail: String = "", anchorDate: Date = Date(),
         topHorizon: Horizon = .fiveYears, sortIndex: Int = 0) {
        self.title = title
        self.detail = detail
        self.anchorDate = anchorDate
        self.topHorizonRaw = topHorizon.rawValue
        self.sortIndex = sortIndex
    }

    var topHorizon: Horizon {
        get { Horizon(rawValue: topHorizonRaw) ?? .fiveYears }
        set { topHorizonRaw = newValue.rawValue }
    }

    var allMilestones: [Milestone] { milestones ?? [] }
    var allReviews: [ReviewLog] { (reviews ?? []).sorted { $0.date > $1.date } }

    var reviewCadence: ReviewCadence {
        get { ReviewCadence(rawValue: reviewCadenceRaw) ?? .weekly }
        set { reviewCadenceRaw = newValue.rawValue }
    }

    /// The most recent review, or (never reviewed) the day the intention was made.
    var lastReviewedAt: Date { allReviews.first?.date ?? createdAt }

    /// When the next review falls due, given the cadence.
    var nextReviewDue: Date {
        ReviewSchedule.nextDue(lastReviewed: lastReviewedAt, cadence: reviewCadence)
    }

    /// Whether a review is due as of `now`.
    func isReviewDue(now: Date = Date()) -> Bool {
        ReviewSchedule.isDue(lastReviewed: lastReviewedAt, cadence: reviewCadence, now: now)
    }

    /// Milestones at a given horizon, ordered.
    func milestones(at h: Horizon) -> [Milestone] {
        allMilestones.filter { $0.horizon == h }.sorted { $0.sortIndex < $1.sortIndex }
    }

    /// Overall progress 0…1 across every milestone (mean of their progress).
    var progress: Double {
        let ms = allMilestones
        guard !ms.isEmpty else { return 0 }
        return ms.map(\.progress).reduce(0, +) / Double(ms.count)
    }
}

/// A milestone assigned to a target horizon, with concrete steps and a
/// definition-of-done ("fait quand…").
@Model
final class Milestone {
    var id: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    var definitionOfDone: String = ""     // "fait quand…"
    var horizonRaw: Int = Horizon.threeMonths.rawValue
    var statusRaw: String = MilestoneStatus.planned.rawValue
    /// Optional explicit target date within the horizon window.
    var targetDate: Date?
    var sortIndex: Int = 0
    var createdAt: Date = Date()
    /// EventKit identifier once this milestone is mirrored to the system Calendar.
    var calendarEventID: String?

    var intention: Intention?

    @Relationship(deleteRule: .cascade, inverse: \Step.milestone)
    var steps: [Step]? = []

    init(title: String, horizon: Horizon, definitionOfDone: String = "",
         notes: String = "", status: MilestoneStatus = .planned,
         targetDate: Date? = nil, sortIndex: Int = 0) {
        self.title = title
        self.horizonRaw = horizon.rawValue
        self.definitionOfDone = definitionOfDone
        self.notes = notes
        self.statusRaw = status.rawValue
        self.targetDate = targetDate
        self.sortIndex = sortIndex
    }

    var horizon: Horizon {
        get { Horizon(rawValue: horizonRaw) ?? .threeMonths }
        set { horizonRaw = newValue.rawValue }
    }

    var status: MilestoneStatus {
        get { MilestoneStatus(rawValue: statusRaw) ?? .planned }
        set { statusRaw = newValue.rawValue }
    }

    var allSteps: [Step] { (steps ?? []).sorted { $0.sortIndex < $1.sortIndex } }

    /// Progress 0…1. If the milestone is explicitly done, 1. Otherwise the
    /// fraction of completed steps; with no steps, planned=0 / active=0.5.
    var progress: Double {
        if status == .done { return 1 }
        let s = allSteps
        if s.isEmpty { return status == .active ? 0.5 : 0 }
        return Double(s.filter(\.isDone).count) / Double(s.count)
    }
}

/// A concrete checklist step inside a milestone.
@Model
final class Step {
    var id: UUID = UUID()
    var text: String = ""
    var isDone: Bool = false
    var sortIndex: Int = 0

    var milestone: Milestone?

    init(text: String, isDone: Bool = false, sortIndex: Int = 0) {
        self.text = text
        self.isDone = isDone
        self.sortIndex = sortIndex
    }
}

/// One entry in an intention's review log — what was advanced, what slipped, and
/// any AI re-flow note captured during a revue.
@Model
final class ReviewLog {
    var id: UUID = UUID()
    var date: Date = Date()
    var cadenceRaw: String = ReviewCadence.weekly.rawValue
    var summary: String = ""              // human/AI summary of the review
    var advancedCount: Int = 0
    var slippedCount: Int = 0
    var reflowNote: String = ""           // AI re-flow suggestion text

    var intention: Intention?

    init(date: Date = Date(), cadence: ReviewCadence = .weekly, summary: String = "",
         advancedCount: Int = 0, slippedCount: Int = 0, reflowNote: String = "") {
        self.date = date
        self.cadenceRaw = cadence.rawValue
        self.summary = summary
        self.advancedCount = advancedCount
        self.slippedCount = slippedCount
        self.reflowNote = reflowNote
    }

    var cadence: ReviewCadence {
        get { ReviewCadence(rawValue: cadenceRaw) ?? .weekly }
        set { cadenceRaw = newValue.rawValue }
    }
}

enum ReviewCadence: String, Codable, CaseIterable, Identifiable {
    case weekly, monthly, seasonal
    var id: String { rawValue }
    func label(_ lang: Lang) -> String {
        switch self {
        case .weekly:   return lang == .fr ? "hebdomadaire" : "weekly"
        case .monthly:  return lang == .fr ? "mensuelle"    : "monthly"
        case .seasonal: return lang == .fr ? "saisonnière"  : "seasonal"
        }
    }
}
