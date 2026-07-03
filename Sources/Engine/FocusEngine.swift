import Foundation

/// Why a milestone surfaced in the "Maintenant" focus view.
enum FocusReason: String, CaseIterable {
    case slipped      // missed its window — needs rescue first
    case active       // already in progress
    case dueSoon      // lands within the focus window
    case nearHorizon  // sits in the nearest (3-month) horizon

    func label(_ lang: Lang) -> String {
        switch self {
        case .slipped:     return lang == .fr ? "à rattraper"   : "to rescue"
        case .active:      return lang == .fr ? "en cours"      : "in progress"
        case .dueSoon:     return lang == .fr ? "bientôt dû"    : "due soon"
        case .nearHorizon: return lang == .fr ? "prochain pas"  : "next up"
        }
    }
}

/// A value-type view of a milestone, so the selection logic stays pure.
struct FocusCandidate {
    let id: UUID
    let horizon: Horizon
    let status: MilestoneStatus
    let effectiveDate: Date
    let openSteps: Int
}

struct FocusItem: Identifiable {
    let id: UUID
    let reason: FocusReason
    let effectiveDate: Date
}

/// Picks and orders the milestones that deserve attention *now* across every
/// intention — the antidote to staring at a five-year board. Pure and testable.
enum FocusEngine {

    /// Select non-done milestones that are slipped, active, due within
    /// `windowDays`, or sitting in the nearest horizon; order them by urgency
    /// (rescue → in-progress → soonest date → nearest horizon).
    static func select(_ candidates: [FocusCandidate], now: Date = Date(),
                       windowDays: Int = 21, calendar: Calendar = .horizon) -> [FocusItem] {
        let windowEnd = calendar.date(byAdding: .day, value: windowDays, to: now) ?? now
        let items: [FocusItem] = candidates.compactMap { c in
            guard c.status != .done else { return nil }
            let reason: FocusReason
            if c.status == .slipped { reason = .slipped }
            else if c.status == .active { reason = .active }
            else if c.effectiveDate <= windowEnd { reason = .dueSoon }
            else if c.horizon == .threeMonths { reason = .nearHorizon }
            else { return nil }
            return FocusItem(id: c.id, reason: reason, effectiveDate: c.effectiveDate)
        }
        let priority: [FocusReason: Int] = [.slipped: 0, .active: 1, .dueSoon: 2, .nearHorizon: 3]
        return items.sorted {
            let p0 = priority[$0.reason] ?? 9, p1 = priority[$1.reason] ?? 9
            return p0 != p1 ? p0 < p1 : $0.effectiveDate < $1.effectiveDate
        }
    }
}
