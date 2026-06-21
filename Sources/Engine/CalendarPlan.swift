import Foundation

/// Pure, UI-free helpers for the calendar workspace: month/week layout, the
/// real-calendar date a milestone occupies, and working-day counting that honours
/// the weekend/holiday toggles. Everything is deterministic on `Calendar.horizon`
/// (Gregorian, Monday-first) so it unit-tests without any UI or SwiftData.
enum CalendarPlan {

    // MARK: Day / month arithmetic

    static func startOfDay(_ date: Date, _ cal: Calendar = .horizon) -> Date {
        cal.startOfDay(for: date)
    }

    /// First instant of the month containing `date`.
    static func monthStart(_ date: Date, _ cal: Calendar = .horizon) -> Date {
        cal.date(from: cal.dateComponents([.year, .month], from: date))!
    }

    /// Month-start dates from `start`'s month through `end`'s month, inclusive.
    static func months(from start: Date, to end: Date, _ cal: Calendar = .horizon) -> [Date] {
        var result: [Date] = []
        var m = monthStart(start, cal)
        let last = monthStart(end, cal)
        while m <= last {
            result.append(m)
            guard let next = cal.date(byAdding: .month, value: 1, to: m) else { break }
            m = next
        }
        return result
    }

    /// The weeks of `month` as rows of seven day-starts, Monday…Sunday, padded
    /// with leading/trailing days from the adjacent months so each row is full.
    static func weeks(of month: Date, _ cal: Calendar = .horizon) -> [[Date]] {
        let first = monthStart(month, cal)
        let firstWeekday = cal.component(.weekday, from: first)        // 1=Sun…7=Sat
        let lead = (firstWeekday - cal.firstWeekday + 7) % 7           // days back to the grid's first cell
        let gridStart = cal.date(byAdding: .day, value: -lead, to: first)!
        let daysInMonth = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        let totalCells = Int((Double(lead + daysInMonth) / 7).rounded(.up)) * 7
        return (0 ..< totalCells / 7).map { week in
            (0 ..< 7).map { day in
                cal.date(byAdding: .day, value: week * 7 + day, to: gridStart)!
            }
        }
    }

    /// Saturday or Sunday.
    static func isWeekend(_ date: Date, _ cal: Calendar = .horizon) -> Bool {
        let wd = cal.component(.weekday, from: date)
        return wd == 1 || wd == 7
    }

    static func isSameDay(_ a: Date, _ b: Date, _ cal: Calendar = .horizon) -> Bool {
        cal.isDate(a, inSameDayAs: b)
    }

    static func isSameMonth(_ a: Date, _ b: Date, _ cal: Calendar = .horizon) -> Bool {
        cal.component(.month, from: a) == cal.component(.month, from: b)
            && cal.component(.year, from: a) == cal.component(.year, from: b)
    }

    // MARK: Milestones on the calendar

    /// The real-calendar day a milestone lands on: its explicit target date if
    /// set, otherwise the close of its horizon window measured from `anchor`.
    static func effectiveDate(targetDate: Date?, horizon: Horizon, anchor: Date,
                              _ cal: Calendar = .horizon) -> Date {
        startOfDay(targetDate ?? horizon.windowEnd(from: anchor, calendar: cal), cal)
    }

    // MARK: Working-day counting

    /// Working days strictly after `from` up to and including `to`. Weekends are
    /// always excluded (that is what "working" means); holidays are excluded only
    /// when `excludeHolidays` is on, so the calendar's holiday toggle changes the
    /// number it reports. Returns 0 when `to` is not after `from`.
    static func workingDays(from: Date, to: Date, holidays: Set<Date>,
                            excludeHolidays: Bool, _ cal: Calendar = .horizon) -> Int {
        let start = startOfDay(from, cal)
        let end = startOfDay(to, cal)
        guard end > start else { return 0 }
        var count = 0
        var d = cal.date(byAdding: .day, value: 1, to: start)!
        while d <= end {
            if !isWeekend(d, cal) && !(excludeHolidays && holidays.contains(d)) {
                count += 1
            }
            d = cal.date(byAdding: .day, value: 1, to: d)!
        }
        return count
    }
}
