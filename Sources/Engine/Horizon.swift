import Foundation

/// The five stacked time horizons — the spine of L'Horizon. A long-horizon
/// intention is broken down into milestones placed at progressively shorter
/// horizons; the cascade reads 5 ans → 3 ans → 1 an → 6 mois → 3 mois.
///
/// `months` is the number of months from a given anchor date that the horizon's
/// window closes. The horizon math (which window a date falls in), the cascade
/// ordering, and the re-flow planner are all pure functions on this type so they
/// can be unit-tested without any UI or SwiftData.
enum Horizon: Int, CaseIterable, Codable, Identifiable, Comparable {
    case threeMonths = 3
    case sixMonths = 6
    case oneYear = 12
    case threeYears = 36
    case fiveYears = 60

    var id: Int { rawValue }

    /// Months from the anchor to the close of this horizon's window.
    var months: Int { rawValue }

    /// Nearest (shortest) horizon first → furthest last. This is the *cascade*
    /// order used to lay the five lanes out near→far.
    static var cascade: [Horizon] { [.threeMonths, .sixMonths, .oneYear, .threeYears, .fiveYears] }

    /// Comparable by window length: a shorter horizon is "less than" a longer one.
    static func < (lhs: Horizon, rhs: Horizon) -> Bool { lhs.months < rhs.months }

    /// FR/EN short label, e.g. "3 mois" / "3 mo".
    func label(_ lang: Lang) -> String {
        switch self {
        case .threeMonths: return lang == .fr ? "3 mois" : "3 mo"
        case .sixMonths:   return lang == .fr ? "6 mois" : "6 mo"
        case .oneYear:     return lang == .fr ? "1 an"   : "1 yr"
        case .threeYears:  return lang == .fr ? "3 ans"  : "3 yr"
        case .fiveYears:   return lang == .fr ? "5 ans"  : "5 yr"
        }
    }

    /// A longer descriptive phrase for the season header.
    func phrase(_ lang: Lang) -> String {
        switch self {
        case .threeMonths: return lang == .fr ? "le trimestre" : "this quarter"
        case .sixMonths:   return lang == .fr ? "le semestre"  : "this half-year"
        case .oneYear:     return lang == .fr ? "l'année"      : "this year"
        case .threeYears:  return lang == .fr ? "les trois ans" : "three years out"
        case .fiveYears:   return lang == .fr ? "les cinq ans"  : "five years out"
        }
    }

    /// The date this horizon's window closes, measured from `anchor`.
    func windowEnd(from anchor: Date, calendar: Calendar = .horizon) -> Date {
        calendar.date(byAdding: .month, value: months, to: anchor) ?? anchor
    }

    /// The previous (shorter) horizon's close — i.e. the *start* of this
    /// horizon's exclusive window. For the shortest horizon this is the anchor.
    func windowStart(from anchor: Date, calendar: Calendar = .horizon) -> Date {
        guard let idx = Horizon.cascade.firstIndex(of: self), idx > 0 else { return anchor }
        return Horizon.cascade[idx - 1].windowEnd(from: anchor, calendar: calendar)
    }

    /// The shorter neighbour in the cascade (closer to now), if any. Used by the
    /// re-flow planner to pull a slipped milestone forward.
    var shorter: Horizon? {
        guard let idx = Horizon.cascade.firstIndex(of: self), idx > 0 else { return nil }
        return Horizon.cascade[idx - 1]
    }

    /// The longer neighbour in the cascade (further out), if any. Used to push a
    /// milestone that can't realistically be met to the next horizon.
    var longer: Horizon? {
        guard let idx = Horizon.cascade.firstIndex(of: self), idx < Horizon.cascade.count - 1 else { return nil }
        return Horizon.cascade[idx + 1]
    }

    /// Classify an arbitrary target date (relative to `anchor`) into the horizon
    /// whose window it falls in. A date at or before the anchor, or within the
    /// first window, is `.threeMonths`; beyond five years clamps to `.fiveYears`.
    static func containing(_ date: Date, anchor: Date, calendar: Calendar = .horizon) -> Horizon {
        for h in cascade where date <= h.windowEnd(from: anchor, calendar: calendar) {
            return h
        }
        return .fiveYears
    }
}

extension Calendar {
    /// A stable calendar for all horizon math — Gregorian, the device time zone,
    /// week starting Monday (Québec convention). Pinned so tests are
    /// deterministic regardless of locale.
    static var horizon: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2 // Monday
        return c
    }
}
