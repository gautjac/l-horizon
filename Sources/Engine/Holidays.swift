import Foundation

/// A statutory / public holiday on a specific day, with a bilingual name. The
/// calendar overlays these so a filmmaker planning shoot days can see which days
/// are off. Pure value type — computed, never stored.
struct Holiday: Identifiable, Equatable {
    /// Start-of-day in `Calendar.horizon`.
    let date: Date
    let nameFR: String
    let nameEN: String

    var id: Date { date }
    func name(_ lang: Lang) -> String { lang == .fr ? nameFR : nameEN }
}

/// Which statutory-holiday set to overlay. Québec is the default (Jac is
/// Québécois); Canada is the federal set; none disables the overlay entirely.
enum HolidayRegion: String, CaseIterable, Identifiable, Codable {
    case quebec, canada, none

    var id: String { rawValue }

    func label(_ lang: Lang) -> String {
        switch self {
        case .quebec: return lang == .fr ? "Québec" : "Quebec"
        case .canada: return lang == .fr ? "Canada" : "Canada"
        case .none:   return lang == .fr ? "Aucun"  : "None"
        }
    }
}

/// Pure statutory-holiday calculator. Every date is computed from the rule
/// (fixed day, n-th weekday, Easter-relative) so the set is correct for any year
/// with no bundled table — and fully unit-testable on `Calendar.horizon`.
enum Holidays {

    // MARK: Public API

    /// The statutory holidays for `region` in calendar `year`, date-sorted.
    static func list(_ region: HolidayRegion, year: Int, calendar cal: Calendar = .horizon) -> [Holiday] {
        switch region {
        case .none:   return []
        case .quebec: return quebec(year: year, calendar: cal)
        case .canada: return canada(year: year, calendar: cal)
        }
    }

    /// All holidays for `region` across an inclusive span of years.
    static func list(_ region: HolidayRegion, years: ClosedRange<Int>,
                     calendar cal: Calendar = .horizon) -> [Holiday] {
        years.flatMap { list(region, year: $0, calendar: cal) }.sorted { $0.date < $1.date }
    }

    /// A fast start-of-day → holiday lookup for a span of years.
    static func map(_ region: HolidayRegion, years: ClosedRange<Int>,
                    calendar cal: Calendar = .horizon) -> [Date: Holiday] {
        Dictionary(list(region, years: years, calendar: cal).map { ($0.date, $0) },
                   uniquingKeysWith: { first, _ in first })
    }

    /// Just the date set — handy for working-day counting.
    static func dateSet(_ region: HolidayRegion, years: ClosedRange<Int>,
                        calendar cal: Calendar = .horizon) -> Set<Date> {
        Set(list(region, years: years, calendar: cal).map(\.date))
    }

    // MARK: Regional sets

    /// Québec statutory holidays (Loi sur les normes du travail). Vendredi saint
    /// *and* Lundi de Pâques are both surfaced — employers choose one, but a
    /// planning calendar should show both candidate days off.
    static func quebec(year y: Int, calendar cal: Calendar = .horizon) -> [Holiday] {
        let easterSun = easter(year: y, cal)
        let goodFriday   = cal.date(byAdding: .day, value: -2, to: easterSun)!
        let easterMonday = cal.date(byAdding: .day, value:  1, to: easterSun)!
        return [
            Holiday(date: ymd(y, 1, 1, cal),  nameFR: "Jour de l'An", nameEN: "New Year's Day"),
            Holiday(date: goodFriday,         nameFR: "Vendredi saint", nameEN: "Good Friday"),
            Holiday(date: easterMonday,       nameFR: "Lundi de Pâques", nameEN: "Easter Monday"),
            Holiday(date: mondayPreceding(month: 5, day: 25, year: y, cal),
                    nameFR: "Journée nationale des patriotes", nameEN: "National Patriots' Day"),
            Holiday(date: ymd(y, 6, 24, cal), nameFR: "Fête nationale", nameEN: "Saint-Jean-Baptiste Day"),
            Holiday(date: ymd(y, 7, 1, cal),  nameFR: "Fête du Canada", nameEN: "Canada Day"),
            Holiday(date: nthWeekday(1, monday, month: 9,  year: y, cal),
                    nameFR: "Fête du Travail", nameEN: "Labour Day"),
            Holiday(date: nthWeekday(2, monday, month: 10, year: y, cal),
                    nameFR: "Action de grâce", nameEN: "Thanksgiving"),
            Holiday(date: ymd(y, 12, 25, cal), nameFR: "Noël", nameEN: "Christmas Day"),
        ].sorted { $0.date < $1.date }
    }

    /// Canadian federal statutory holidays.
    static func canada(year y: Int, calendar cal: Calendar = .horizon) -> [Holiday] {
        let easterSun = easter(year: y, cal)
        let goodFriday = cal.date(byAdding: .day, value: -2, to: easterSun)!
        return [
            Holiday(date: ymd(y, 1, 1, cal),  nameFR: "Jour de l'An", nameEN: "New Year's Day"),
            Holiday(date: goodFriday,         nameFR: "Vendredi saint", nameEN: "Good Friday"),
            Holiday(date: mondayPreceding(month: 5, day: 25, year: y, cal),
                    nameFR: "Fête de la Reine", nameEN: "Victoria Day"),
            Holiday(date: ymd(y, 7, 1, cal),  nameFR: "Fête du Canada", nameEN: "Canada Day"),
            Holiday(date: nthWeekday(1, monday, month: 9,  year: y, cal),
                    nameFR: "Fête du Travail", nameEN: "Labour Day"),
            Holiday(date: ymd(y, 9, 30, cal),
                    nameFR: "Journée de la vérité et de la réconciliation",
                    nameEN: "Truth and Reconciliation Day"),
            Holiday(date: nthWeekday(2, monday, month: 10, year: y, cal),
                    nameFR: "Action de grâce", nameEN: "Thanksgiving"),
            Holiday(date: ymd(y, 11, 11, cal), nameFR: "Jour du Souvenir", nameEN: "Remembrance Day"),
            Holiday(date: ymd(y, 12, 25, cal), nameFR: "Noël", nameEN: "Christmas Day"),
            Holiday(date: ymd(y, 12, 26, cal), nameFR: "Lendemain de Noël", nameEN: "Boxing Day"),
        ].sorted { $0.date < $1.date }
    }

    // MARK: Date-rule helpers

    private static let monday = 2 // Calendar weekday: 1=Sun … 7=Sat.

    private static func ymd(_ y: Int, _ m: Int, _ d: Int, _ cal: Calendar) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    /// The `n`-th day-of-week `weekday` (1=Sun…7=Sat) in `month`/`year`.
    private static func nthWeekday(_ n: Int, _ weekday: Int, month: Int, year: Int,
                                   _ cal: Calendar) -> Date {
        let first = ymd(year, month, 1, cal)
        let firstWd = cal.component(.weekday, from: first)
        let offset = ((weekday - firstWd + 7) % 7) + (n - 1) * 7
        return cal.date(byAdding: .day, value: offset, to: first)!
    }

    /// The Monday strictly preceding `month`/`day` — the rule for Victoria Day /
    /// National Patriots' Day ("the Monday preceding May 25").
    private static func mondayPreceding(month: Int, day: Int, year: Int, _ cal: Calendar) -> Date {
        var d = cal.date(byAdding: .day, value: -1, to: ymd(year, month, day, cal))!
        while cal.component(.weekday, from: d) != monday {
            d = cal.date(byAdding: .day, value: -1, to: d)!
        }
        return d
    }

    /// Easter Sunday (Gregorian) via the Anonymous Gregorian algorithm (Meeus).
    private static func easter(year: Int, _ cal: Calendar) -> Date {
        let a = year % 19
        let b = year / 100, c = year % 100
        let d = b / 4, e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1
        return ymd(year, month, day, cal)
    }
}
