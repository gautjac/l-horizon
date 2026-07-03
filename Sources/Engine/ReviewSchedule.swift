import Foundation

/// Pure scheduling math for the review ritual: given when an intention was last
/// reviewed and its cadence, when is the next review due, and is it due now.
/// Deterministic on `Calendar.horizon` so it unit-tests without any UI.
enum ReviewSchedule {

    /// The gap between reviews for a cadence.
    static func interval(_ cadence: ReviewCadence) -> DateComponents {
        switch cadence {
        case .weekly:   return DateComponents(day: 7)
        case .monthly:  return DateComponents(month: 1)
        case .seasonal: return DateComponents(month: 3)
        }
    }

    /// The moment the next review falls due after `lastReviewed`.
    static func nextDue(lastReviewed: Date, cadence: ReviewCadence,
                        calendar: Calendar = .horizon) -> Date {
        calendar.date(byAdding: interval(cadence), to: lastReviewed) ?? lastReviewed
    }

    /// Whether a review is due at `now` (i.e. now is at or past the next-due date).
    static func isDue(lastReviewed: Date, cadence: ReviewCadence,
                      now: Date = Date(), calendar: Calendar = .horizon) -> Bool {
        now >= nextDue(lastReviewed: lastReviewed, cadence: cadence, calendar: calendar)
    }

    /// Whole days from `now` until the next review — negative when overdue.
    static func daysUntilDue(lastReviewed: Date, cadence: ReviewCadence,
                             now: Date = Date(), calendar: Calendar = .horizon) -> Int {
        let due = nextDue(lastReviewed: lastReviewed, cadence: cadence, calendar: calendar)
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                       to: calendar.startOfDay(for: due)).day ?? 0
    }
}
