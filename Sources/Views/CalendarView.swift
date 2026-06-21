import SwiftUI
import SwiftData

/// The calendar workspace: every milestone plotted on a real wall calendar, in a
/// choice of three layouts — a single big **Mois** (month), a full-year **Année**
/// poster, or the rolling **Grille** strip — all built to fill a wide desk-class
/// window (full screen on a 32"). Weekends and holidays can each be toggled on
/// and off; holidays come from a selectable region (Québec by default). Clicking a
/// day plants a new milestone there; clicking a chip opens its editor.
struct CalendarWorkspaceView: View {
    @EnvironmentObject var loc: LocManager
    @Environment(\.modelContext) private var context
    @Bindable var intention: Intention

    // Persisted across launches under shared Atelier-style keys.
    @AppStorage("atelier_lhorizon_cal_weekends") private var showWeekends = true
    @AppStorage("atelier_lhorizon_cal_holidays") private var showHolidays = true
    @AppStorage("atelier_lhorizon_cal_region")   private var regionRaw = HolidayRegion.quebec.rawValue
    @AppStorage("atelier_lhorizon_cal_span")     private var spanMonths = 12
    @AppStorage("atelier_lhorizon_cal_mode")     private var modeRaw = CalendarLayoutMode.grid.rawValue

    @State private var editTarget: EditTarget?
    @State private var createTarget: CreateTarget?
    // Navigation focus for the Mois / Année layouts.
    @State private var focusMonth = Date()
    @State private var focusYear = 0
    // Timeline zoom: 1 = fit the whole span to the window (no scroll), up.
    @State private var timelineZoom: CGFloat = 1

    private let cal = Calendar.horizon
    private var region: HolidayRegion { HolidayRegion(rawValue: regionRaw) ?? .quebec }
    private var mode: CalendarLayoutMode { CalendarLayoutMode(rawValue: modeRaw) ?? .month }
    private var today: Date { cal.startOfDay(for: Date()) }

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            Divider().overlay(Theme.line.opacity(0.12))
            content
        }
        .onAppear {
            focusMonth = CalendarPlan.monthStart(today, cal)
            if focusYear == 0 { focusYear = cal.component(.year, from: today) }
        }
        .sheet(item: $editTarget) { target in
            if let m = intention.allMilestones.first(where: { $0.id == target.id }) {
                MilestoneEditor(milestone: m)
            }
        }
        .sheet(item: $createTarget) { target in
            MilestoneEditor(milestone: nil,
                            intention: intention,
                            horizon: Horizon.containing(target.date, anchor: intention.anchorDate),
                            presetDate: target.date)
        }
    }

    // MARK: Layouts

    /// The scrollable body. Month & year scroll vertically; the grid is a true
    /// horizontal calendar — one row of months you scroll left-to-right.
    @ViewBuilder private var content: some View {
        switch mode {
        case .month:
            ScrollView { monthLayout.padding(22) }
        case .year:
            ScrollView { yearLayout.padding(22) }
        case .grid:
            TimelineRibbon(intention: intention,
                           months: spanMonthsList,
                           horizonEnds: horizonEnds,
                           today: today,
                           zoom: $timelineZoom,
                           onSelect: { editTarget = EditTarget(id: $0) })
                .padding(.top, 4)
        }
    }

    /// One large month, centred, navigable month-to-month.
    private var monthLayout: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            monthCard(CalendarPlan.monthStart(focusMonth, cal), metrics: .large)
                .frame(maxWidth: 1400)
            Spacer(minLength: 0)
        }
    }

    /// All twelve months of the focused year as a poster grid.
    private var yearLayout: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 420),
                                     spacing: 18, alignment: .top)],
                  alignment: .leading, spacing: 18) {
            ForEach(monthsOfYear(focusYear), id: \.self) { monthCard($0, metrics: .compact) }
        }
    }

    private func monthCard(_ month: Date, metrics: CalMetrics) -> some View {
        MonthCard(month: month,
                  intention: intention,
                  milestonesByDay: milestonesByDay,
                  holidayMap: holidayMap,
                  horizonEndsByMonth: horizonEndsByMonth,
                  showWeekends: showWeekends,
                  showHolidays: showHolidays,
                  today: today,
                  metrics: metrics,
                  onSelect: { editTarget = EditTarget(id: $0) },
                  onCreate: { createTarget = CreateTarget(date: $0) })
    }

    // MARK: Control bar

    private var controlBar: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(intention.title)
                        .font(Theme.display(20)).foregroundStyle(.white).lineLimit(1)
                    Text(loc.t("Le plan, jour par jour", "The plan, day by day"))
                        .font(Theme.displayLight(11)).italic().foregroundStyle(.white.opacity(0.55))
                }
                Spacer(minLength: 12)
                workdayStat
            }
            HStack(alignment: .center, spacing: 8) {
                modeSwitcher
                Divider().frame(height: 22).overlay(Theme.line.opacity(0.18))
                contextControls
                Spacer(minLength: 8)
                pill(title: loc.t("Fins de semaine", "Weekends"),
                     icon: showWeekends ? "calendar" : "calendar.day.timeline.left",
                     on: showWeekends) { showWeekends.toggle() }
                pill(title: loc.t("Jours fériés", "Holidays"),
                     icon: showHolidays ? "flag.fill" : "flag",
                     on: showHolidays) { showHolidays.toggle() }
                regionMenu
            }
            legend
        }
        .padding(.horizontal, 22)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    /// Mois / Année / Grille switcher.
    private var modeSwitcher: some View {
        HStack(spacing: 6) {
            ForEach(CalendarLayoutMode.allCases) { m in
                pill(title: m.label(loc.lang), icon: m.icon, on: mode == m) { modeRaw = m.rawValue }
            }
        }
    }

    /// Span menu in grid mode; prev/next/today nav in month & year modes.
    @ViewBuilder private var contextControls: some View {
        switch mode {
        case .grid:
            HStack(spacing: 8) {
                spanMenu
                Divider().frame(height: 18).overlay(Theme.line.opacity(0.18))
                zoomControls
            }
        case .month:
            navControls(label: monthLabel(focusMonth),
                        back: { focusMonth = cal.date(byAdding: .month, value: -1, to: focusMonth)! },
                        forward: { focusMonth = cal.date(byAdding: .month, value: 1, to: focusMonth)! },
                        today: { focusMonth = CalendarPlan.monthStart(today, cal) })
        case .year:
            navControls(label: "\(focusYear)",
                        back: { focusYear -= 1 },
                        forward: { focusYear += 1 },
                        today: { focusYear = cal.component(.year, from: today) })
        }
    }

    private func navControls(label: String, back: @escaping () -> Void,
                             forward: @escaping () -> Void, today: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            navButton("chevron.left", back)
            Text(label).font(Theme.display(15)).foregroundStyle(.white)
                .frame(minWidth: 116)
            navButton("chevron.right", forward)
            pill(title: loc.t("Aujourd'hui", "Today"), icon: "scope", on: false, today)
        }
    }

    /// − / Fit / + for the timeline. "Fit" (zoom 1) makes the whole span fill the
    /// window with no horizontal scroll; + and trackpad pinch zoom in for detail.
    private var zoomControls: some View {
        HStack(spacing: 6) {
            navButton("minus") { withAnimation(.easeOut(duration: 0.15)) { timelineZoom = max(1, timelineZoom / 1.5) } }
            Button { withAnimation(.easeOut(duration: 0.15)) { timelineZoom = 1 } } label: {
                pillLabel(title: timelineZoom <= 1.01 ? loc.t("Ajusté", "Fit")
                                                       : String(format: "×%.1f", timelineZoom),
                          icon: "arrow.up.left.and.down.right.magnifyingglass",
                          on: timelineZoom > 1.01)
            }
            .buttonStyle(.plain)
            .help(loc.t("Tout afficher sans défiler", "Fit the whole span — no scrolling"))
            navButton("plus") { withAnimation(.easeOut(duration: 0.15)) { timelineZoom = min(10, timelineZoom * 1.5) } }
        }
    }

    private func navButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 28, height: 28)
                .background(Circle().fill(.white.opacity(0.07)))
        }
        .buttonStyle(.plain)
    }

    /// Live count of working days to the next upcoming milestone — honours the
    /// holiday toggle, so the number is whatever the calendar above is showing.
    private var workdayStat: some View {
        Group {
            if let next = nextUpcoming {
                let n = CalendarPlan.workingDays(from: today, to: next.date,
                                                 holidays: holidaySet,
                                                 excludeHolidays: showHolidays)
                VStack(alignment: .trailing, spacing: 1) {
                    HStack(spacing: 5) {
                        Text("\(n)").font(Theme.display(18)).foregroundStyle(Theme.dawnSoft)
                        Text(loc.t(n == 1 ? "jour ouvrable" : "jours ouvrables",
                                   n == 1 ? "working day" : "working days"))
                            .font(Theme.body(10)).foregroundStyle(.white.opacity(0.7))
                    }
                    Text("→ " + next.milestone.title)
                        .font(Theme.body(9.5)).foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1).frame(maxWidth: 220, alignment: .trailing)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.06)))
            }
        }
    }

    private var regionMenu: some View {
        Menu {
            ForEach(HolidayRegion.allCases) { r in
                Button {
                    regionRaw = r.rawValue
                    showHolidays = (r != .none)
                } label: {
                    Label(r.label(loc.lang), systemImage: region == r ? "checkmark" : "")
                }
            }
        } label: {
            pillLabel(title: region.label(loc.lang), icon: "globe.americas", on: false)
        }
        .menuStyle(.borderlessButton).fixedSize()
    }

    private var spanMenu: some View {
        Menu {
            ForEach(SpanOption.allCases) { opt in
                Button { spanMonths = opt.months } label: {
                    Label(opt.label(loc.lang), systemImage: spanMonths == opt.months ? "checkmark" : "")
                }
            }
        } label: {
            pillLabel(title: loc.t("Portée ", "Span ") + SpanOption.closest(spanMonths).label(loc.lang),
                      icon: "arrow.left.and.right", on: false)
        }
        .menuStyle(.borderlessButton).fixedSize()
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem(swatch: AnyView(Circle().fill(Theme.dawn).frame(width: 9, height: 9)),
                       text: loc.t("aujourd'hui", "today"))
            legendItem(swatch: AnyView(Image(systemName: "mappin.circle.fill")
                .font(.system(size: 9)).foregroundStyle(Theme.dusk)),
                       text: loc.t("ancrage", "anchor"))
            if showWeekends && mode != .grid {
                legendItem(swatch: AnyView(RoundedRectangle(cornerRadius: 2)
                    .fill(Color.black.opacity(0.10)).frame(width: 12, height: 9)),
                           text: loc.t("fin de semaine", "weekend"))
            }
            if showHolidays && region != .none && mode != .grid {
                legendItem(swatch: AnyView(RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.dawn.opacity(0.22)).frame(width: 12, height: 9)),
                           text: loc.t("jour férié", "holiday"))
            }
            legendItem(swatch: AnyView(Image(systemName: "diamond.fill")
                .font(.system(size: 7)).foregroundStyle(Theme.dawnSoft)),
                       text: loc.t("fin d'horizon", "horizon close"))
            legendItem(swatch: AnyView(RoundedRectangle(cornerRadius: 2)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                .foregroundStyle(.white.opacity(0.6)).frame(width: 12, height: 9)),
                       text: loc.t("date estimée", "estimated date"))
            Spacer()
        }
        .foregroundStyle(.white.opacity(0.55))
    }

    private func legendItem(swatch: AnyView, text: String) -> some View {
        HStack(spacing: 5) { swatch; Text(text).font(Theme.body(10)) }
    }

    // MARK: Pills

    private func pill(title: String, icon: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.15)) { action() } }) {
            pillLabel(title: title, icon: icon, on: on)
        }
        .buttonStyle(.plain)
    }

    private func pillLabel(title: String, icon: String, on: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11))
            Text(title).font(Theme.body(12))
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9)
            .fill(on ? Theme.dawn.opacity(0.92) : Color.white.opacity(0.07)))
        .foregroundStyle(on ? Theme.nightDeep : .white.opacity(0.85))
    }

    // MARK: Derived data

    /// Milestones keyed by the day they land on.
    private var milestonesByDay: [Date: [Milestone]] {
        Dictionary(grouping: intention.allMilestones) { m in
            CalendarPlan.effectiveDate(targetDate: m.targetDate, horizon: m.horizon,
                                       anchor: intention.anchorDate, cal)
        }
    }

    /// First month shown in grid mode: the earlier of this month and the earliest milestone.
    private var startMonth: Date {
        let earliest = milestonesByDay.keys.min() ?? today
        return CalendarPlan.monthStart(min(today, earliest), cal)
    }

    private var spanMonthsList: [Date] {
        let end = cal.date(byAdding: .month, value: spanMonths, to: startMonth) ?? startMonth
        return CalendarPlan.months(from: startMonth, to: end, cal)
    }

    private func monthsOfYear(_ year: Int) -> [Date] {
        (1...12).compactMap { cal.date(from: DateComponents(year: year, month: $0, day: 1)) }
    }

    /// The months currently on screen, for sizing the holiday lookup.
    private var visibleMonths: [Date] {
        switch mode {
        case .month: return [CalendarPlan.monthStart(focusMonth, cal)]
        case .year:  return monthsOfYear(focusYear == 0 ? cal.component(.year, from: today) : focusYear)
        case .grid:  return spanMonthsList
        }
    }

    /// Each horizon paired with the real date its window closes — for the
    /// timeline's boundary markers.
    private var horizonEnds: [(Horizon, Date)] {
        Horizon.cascade.map { ($0, CalendarPlan.startOfDay($0.windowEnd(from: intention.anchorDate, calendar: cal), cal)) }
    }

    /// Map of month-start → the horizons whose window closes within that month.
    private var horizonEndsByMonth: [Date: [Horizon]] {
        var out: [Date: [Horizon]] = [:]
        for h in Horizon.cascade {
            let end = CalendarPlan.startOfDay(h.windowEnd(from: intention.anchorDate, calendar: cal), cal)
            out[CalendarPlan.monthStart(end, cal), default: []].append(h)
        }
        return out
    }

    /// Inclusive year range covering the visible months plus a one-year margin so
    /// leading/trailing filler days (which can spill into an adjacent year) resolve.
    private var visibleYears: ClosedRange<Int> {
        let first = visibleMonths.first ?? today
        let last = visibleMonths.last ?? today
        return (cal.component(.year, from: first) - 1) ... (cal.component(.year, from: last) + 1)
    }

    private var holidayMap: [Date: Holiday] {
        guard showHolidays, region != .none else { return [:] }
        return Holidays.map(region, years: visibleYears, calendar: cal)
    }

    private var holidaySet: Set<Date> {
        guard region != .none else { return [] }
        return Holidays.dateSet(region, years: visibleYears, calendar: cal)
    }

    private var nextUpcoming: (milestone: Milestone, date: Date)? {
        intention.allMilestones
            .filter { $0.status != .done }
            .map { (m: $0, d: CalendarPlan.effectiveDate(targetDate: $0.targetDate, horizon: $0.horizon,
                                                         anchor: intention.anchorDate, cal)) }
            .filter { $0.d >= today }
            .min { $0.d < $1.d }
            .map { ($0.m, $0.d) }
    }

    private func monthLabel(_ month: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: loc.lang == .fr ? "fr_CA" : "en_CA")
        df.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return df.string(from: month).capitalized
    }
}

// MARK: - View modes & sheet routing

/// The three calendar layouts.
enum CalendarLayoutMode: String, CaseIterable, Identifiable {
    case month, year, grid
    var id: String { rawValue }
    func label(_ lang: Lang) -> String {
        switch self {
        case .month: return lang == .fr ? "Mois"    : "Month"
        case .year:  return lang == .fr ? "Année"   : "Year"
        case .grid:  return lang == .fr ? "Frise"   : "Timeline"
        }
    }
    var icon: String {
        switch self {
        case .month: return "square.grid.3x3"
        case .year:  return "calendar"
        case .grid:  return "calendar.day.timeline.left"
        }
    }
}

/// Identifiable wrappers so the calendar can drive `.sheet(item:)`.
private struct EditTarget: Identifiable { let id: UUID }
private struct CreateTarget: Identifiable { let date: Date; var id: Date { date } }

/// How far the Grille layout reaches, matching the horizon vocabulary.
private enum SpanOption: Int, CaseIterable, Identifiable {
    case quarter = 3, half = 6, year = 12, threeYears = 36, fiveYears = 60
    var id: Int { rawValue }
    var months: Int { rawValue }
    func label(_ lang: Lang) -> String {
        switch self {
        case .quarter:    return lang == .fr ? "3 mois" : "3 mo"
        case .half:       return lang == .fr ? "6 mois" : "6 mo"
        case .year:       return lang == .fr ? "1 an"   : "1 yr"
        case .threeYears: return lang == .fr ? "3 ans"  : "3 yr"
        case .fiveYears:  return lang == .fr ? "5 ans"  : "5 yr"
        }
    }
    /// The option nearest a stored month count (so a legacy value still maps).
    static func closest(_ months: Int) -> SpanOption {
        allCases.min { abs($0.months - months) < abs($1.months - months) } ?? .year
    }
}

// MARK: - Sizing

/// Sizing for a month card at a given scale — `compact` for the year/strip grids,
/// `large` for the single-month layout.
struct CalMetrics {
    let titleSize, weekdaySize, dayNumberSize, chipFont, holidayFont: CGFloat
    let dayMinHeight, cardPadding, cornerRadius, daySpacing: CGFloat
    let maxChips: Int
    let badges: Bool

    static let compact = CalMetrics(
        titleSize: 17, weekdaySize: 9, dayNumberSize: 10.5, chipFont: 9, holidayFont: 7.5,
        dayMinHeight: 66, cardPadding: 14, cornerRadius: 16, daySpacing: 4, maxChips: 2, badges: true)

    static let large = CalMetrics(
        titleSize: 25, weekdaySize: 12, dayNumberSize: 15, chipFont: 12, holidayFont: 10,
        dayMinHeight: 118, cardPadding: 20, cornerRadius: 20, daySpacing: 6, maxChips: 5, badges: true)
}

// MARK: - Month card

private struct MonthCard: View {
    @EnvironmentObject var loc: LocManager
    let month: Date
    @Bindable var intention: Intention
    let milestonesByDay: [Date: [Milestone]]
    let holidayMap: [Date: Holiday]
    let horizonEndsByMonth: [Date: [Horizon]]
    let showWeekends: Bool
    let showHolidays: Bool
    let today: Date
    let metrics: CalMetrics
    let onSelect: (UUID) -> Void
    let onCreate: (Date) -> Void

    private let cal = Calendar.horizon

    /// Columns to show: all seven, or Mon–Fri (drop the last two).
    private var columns: Range<Int> { showWeekends ? 0..<7 : 0..<5 }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.daySpacing + 4) {
            header
            weekdayHeader
            ForEach(Array(CalendarPlan.weeks(of: month, cal).enumerated()), id: \.offset) { _, week in
                HStack(spacing: metrics.daySpacing) {
                    ForEach(columns, id: \.self) { i in
                        DayCell(date: week[i],
                                month: month,
                                milestones: milestonesByDay[CalendarPlan.startOfDay(week[i], cal)] ?? [],
                                holiday: showHolidays ? holidayMap[CalendarPlan.startOfDay(week[i], cal)] : nil,
                                isToday: CalendarPlan.isSameDay(week[i], today, cal),
                                isAnchor: CalendarPlan.isSameDay(week[i], intention.anchorDate, cal),
                                metrics: metrics,
                                onSelect: onSelect,
                                onCreate: onCreate)
                    }
                }
            }
        }
        .padding(metrics.cardPadding)
        .background(RoundedRectangle(cornerRadius: metrics.cornerRadius).fill(Theme.parchment)
            .shadow(color: .black.opacity(0.26), radius: 8, y: 4))
        .overlay(RoundedRectangle(cornerRadius: metrics.cornerRadius)
            .strokeBorder(isCurrentMonth ? Theme.dawn.opacity(0.55) : Color.clear, lineWidth: 1.5))
    }

    private var isCurrentMonth: Bool { CalendarPlan.isSameMonth(month, today, cal) }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(monthTitle)
                .font(Theme.display(metrics.titleSize)).foregroundStyle(Theme.parchmentInk)
            Spacer()
            if metrics.badges {
                ForEach(horizonEndsByMonth[CalendarPlan.monthStart(month, cal)] ?? [], id: \.self) { h in
                    HStack(spacing: 3) {
                        Image(systemName: "diamond.fill").font(.system(size: 6))
                        Text(h.label(loc.lang)).font(Theme.mono(9))
                    }
                    .foregroundStyle(Theme.accent(h))
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Capsule().fill(Theme.accent(h).opacity(0.16)))
                }
            }
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: metrics.daySpacing) {
            ForEach(columns, id: \.self) { i in
                Text(weekdaySymbols[i])
                    .font(Theme.mono(metrics.weekdaySize)).tracking(0.3)
                    .foregroundStyle(Theme.parchmentInk.opacity(0.45))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // Monday-first short weekday symbols in the active language.
    private var weekdaySymbols: [String] {
        let df = DateFormatter()
        df.locale = Locale(identifier: loc.lang == .fr ? "fr_CA" : "en_CA")
        let syms = df.shortStandaloneWeekdaySymbols ?? ["S","M","T","W","T","F","S"]
        return Array(syms[1...6]) + [syms[0]]    // Mon … Sun
    }

    private var monthTitle: String {
        let df = DateFormatter()
        df.locale = Locale(identifier: loc.lang == .fr ? "fr_CA" : "en_CA")
        df.setLocalizedDateFormatFromTemplate(metrics.badges && metrics.titleSize > 20 ? "MMMM yyyy" : "MMMM")
        return df.string(from: month).capitalized
    }
}

// MARK: - Day cell

private struct DayCell: View {
    @EnvironmentObject var loc: LocManager
    let date: Date
    let month: Date
    let milestones: [Milestone]
    let holiday: Holiday?
    let isToday: Bool
    let isAnchor: Bool
    let metrics: CalMetrics
    let onSelect: (UUID) -> Void
    let onCreate: (Date) -> Void

    @State private var hovering = false
    private let cal = Calendar.horizon

    private var inMonth: Bool { CalendarPlan.isSameMonth(date, month, cal) }
    private var isWeekend: Bool { CalendarPlan.isWeekend(date, cal) }
    private var dayNumber: String { "\(cal.component(.day, from: date))" }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            topRow
            ForEach(milestones.prefix(metrics.maxChips)) { m in chip(m) }
            if milestones.count > metrics.maxChips {
                Text("+\(milestones.count - metrics.maxChips)")
                    .font(Theme.mono(8.5)).foregroundStyle(Theme.parchmentInk.opacity(0.55))
                    .padding(.leading, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(5)
        .frame(maxWidth: .infinity, minHeight: metrics.dayMinHeight, alignment: .topLeading)
        .background(cellBackground)
        .overlay(alignment: .topTrailing) { addAffordance }
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7)
            .strokeBorder(isToday ? Theme.dawn : .clear, lineWidth: 1.5))
        .opacity(inMonth ? 1 : 0.32)
        .onHover { if inMonth { hovering = $0 } }
        .help(holiday.map { $0.name(loc.lang) } ?? "")
    }

    private var topRow: some View {
        HStack(spacing: 4) {
            ZStack {
                if isToday {
                    Circle().fill(Theme.dawn)
                        .frame(width: metrics.dayNumberSize + 7, height: metrics.dayNumberSize + 7)
                }
                Text(dayNumber)
                    .font(Theme.mono(metrics.dayNumberSize))
                    .foregroundStyle(isToday ? Theme.nightDeep
                                     : (isWeekend ? Theme.parchmentInk.opacity(0.5) : Theme.parchmentInk))
            }
            if isAnchor {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: metrics.dayNumberSize - 2)).foregroundStyle(Theme.dusk)
                    .help(loc.t("Ancrage", "Anchor"))
            }
            Spacer(minLength: 0)
            if let h = holiday, inMonth {
                Text(h.name(loc.lang))
                    .font(Theme.body(metrics.holidayFont)).lineLimit(1)
                    .foregroundStyle(Theme.dawn.opacity(0.95))
                    .frame(maxWidth: metrics.maxChips > 2 ? 120 : 64, alignment: .trailing)
            }
        }
    }

    /// A milestone chip — horizon-coloured, status dot, dashed when the date is
    /// only an estimate (no explicit target).
    private func chip(_ m: Milestone) -> some View {
        Button { onSelect(m.id) } label: {
            HStack(spacing: 4) {
                Circle().fill(Theme.statusColor(m.status)).frame(width: 5, height: 5)
                Text(m.title).font(Theme.body(metrics.chipFont)).lineLimit(1)
                    .foregroundStyle(Theme.parchmentInk)
            }
            .padding(.horizontal, 5).padding(.vertical, 2.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 5).fill(Theme.accent(m.horizon).opacity(0.30)))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(
                Theme.accent(m.horizon).opacity(0.85),
                style: StrokeStyle(lineWidth: 1, dash: m.targetDate == nil ? [2, 2] : [])))
        }
        .buttonStyle(.plain)
        .help(m.title + (m.targetDate == nil ? " — " + loc.t("date estimée", "estimated date") : ""))
    }

    @ViewBuilder private var addAffordance: some View {
        if hovering && milestones.isEmpty {
            Button { onCreate(date) } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.dawn.opacity(0.9))
                    .background(Circle().fill(Theme.parchment))
            }
            .buttonStyle(.plain)
            .padding(3)
            .help(loc.t("Nouveau jalon ce jour", "New milestone on this day"))
        }
    }

    private var cellBackground: Color {
        if holiday != nil { return Theme.dawn.opacity(0.18) }
        if isWeekend { return Color.black.opacity(0.07) }
        return Color.black.opacity(0.015)
    }
}

// MARK: - Timeline ribbon (Frise)

/// A continuous left-to-right roadmap: one horizontal time axis, the five
/// horizons stacked as tracks, and every milestone placed as a pill at its real
/// date. Month/year gridlines, dashed horizon-window markers, and today/anchor
/// lines run the full height. Pills pack into sub-rows so they never overlap; a
/// pinned left column keeps the lane labels in view while the axis scrolls.
private struct TimelineRibbon: View {
    @EnvironmentObject var loc: LocManager
    let intention: Intention
    let months: [Date]
    let horizonEnds: [(Horizon, Date)]
    let today: Date
    @Binding var zoom: CGFloat
    let onSelect: (UUID) -> Void

    private let cal = Calendar.horizon
    private let labelW: CGFloat = 96
    private let axisH: CGFloat = 48
    private let chipW: CGFloat = 158
    private let chipH: CGFloat = 24
    private let subGap: CGFloat = 6
    private let laneVPad: CGFloat = 14
    private let hPad: CGFloat = 18
    private let minPx: CGFloat = 0.25
    static let maxZoom: CGFloat = 10

    /// Live trackpad-pinch scale, composed with the committed `zoom`.
    @GestureState private var pinch: CGFloat = 1

    private var lanes: [Horizon] { Horizon.cascade }

    // MARK: Time → space

    private var rangeStart: Date { CalendarPlan.startOfDay(months.first ?? today, cal) }
    private var rangeEndExclusive: Date {
        let last = months.last ?? rangeStart
        return CalendarPlan.startOfDay(cal.date(byAdding: .month, value: 1, to: last) ?? last, cal)
    }
    private var totalDays: Int {
        max(1, cal.dateComponents([.day], from: rangeStart, to: rangeEndExclusive).day ?? 1)
    }

    /// Effective zoom = committed zoom × live pinch, clamped. 1 = fit-to-window.
    private var effectiveZoom: CGFloat { min(Self.maxZoom, max(1, zoom * pinch)) }

    /// Pixels-per-day that makes the whole span exactly fill `width` at zoom 1, so
    /// the default view shows everything with no horizontal scroll.
    private func fitPx(_ width: CGFloat) -> CGFloat {
        let usable = width - labelW - hPad * 2 - chipW - 28
        return max(minPx, usable / CGFloat(totalDays))
    }
    private func pxPerDay(_ width: CGFloat) -> CGFloat { fitPx(width) * effectiveZoom }
    private func contentW(_ px: CGFloat) -> CGFloat { CGFloat(totalDays) * px + chipW + 28 }

    private func dayOffset(_ d: Date) -> Int {
        max(0, cal.dateComponents([.day], from: rangeStart, to: CalendarPlan.startOfDay(d, cal)).day ?? 0)
    }
    private func x(_ d: Date, _ px: CGFloat) -> CGFloat { CGFloat(dayOffset(d)) * px }
    private func inRange(_ d: Date) -> Bool { d >= rangeStart && d < rangeEndExclusive }
    private func eff(_ m: Milestone) -> Date {
        CalendarPlan.effectiveDate(targetDate: m.targetDate, horizon: m.horizon, anchor: intention.anchorDate, cal)
    }

    /// Draw a month gridline/label every Nth month so a zoomed-out span stays legible.
    private func labelStride(_ px: CGFloat) -> Int {
        let monthW = px * 30.4
        if monthW >= 42 { return 1 }
        if monthW >= 20 { return 3 }
        if monthW >= 11 { return 6 }
        return 12
    }

    // MARK: Lane packing

    private struct Placed: Identifiable { let id: UUID; let m: Milestone; let x: CGFloat; let lane: Int; let sub: Int }

    /// Greedily pack each lane's milestones into non-overlapping sub-rows.
    private func layout(_ px: CGFloat) -> (placements: [Placed], laneSubs: [Int]) {
        var placements: [Placed] = []
        var laneSubs = Array(repeating: 1, count: lanes.count)
        for (li, h) in lanes.enumerated() {
            let ms = intention.allMilestones.filter { $0.horizon == h }.sorted { eff($0) < eff($1) }
            var rowRight: [CGFloat] = []
            for m in ms {
                let sx = x(eff(m), px)
                var sub = rowRight.firstIndex { sx > $0 + 6 } ?? -1
                if sub == -1 { rowRight.append(sx + chipW); sub = rowRight.count - 1 }
                else { rowRight[sub] = sx + chipW }
                placements.append(Placed(id: m.id, m: m, x: sx, lane: li, sub: sub))
            }
            laneSubs[li] = max(1, rowRight.count)
        }
        return (placements, laneSubs)
    }

    private let markerRowH: CGFloat = 15
    private func laneHeight(_ subs: Int) -> CGFloat { CGFloat(subs) * (chipH + subGap) + laneVPad }
    private func laneOriginY(_ lane: Int, _ subs: [Int], _ headerH: CGFloat) -> CGFloat {
        headerH + (0..<lane).reduce(0) { $0 + laneHeight(subs[$1]) }
    }
    private func totalH(_ subs: [Int], _ headerH: CGFloat) -> CGFloat {
        headerH + subs.reduce(0) { $0 + laneHeight($1) }
    }

    // MARK: Top markers (today, anchor, horizon closes), packed to avoid overlap

    private struct Marker: Identifiable {
        let id = UUID()
        let x: CGFloat; let w: CGFloat; let text: String
        let color: Color; let icon: String; let filled: Bool; let row: Int
    }

    /// Lay the today + horizon-close labels into stacked rows so that, when the
    /// span is zoomed out and several closes bunch together, their labels never
    /// overlap. (The anchor is a bare line, no label.)
    private func markerLayout(_ px: CGFloat) -> [Marker] {
        struct Raw { let x: CGFloat; let w: CGFloat; let text: String; let color: Color; let icon: String; let filled: Bool }
        var raws: [Raw] = []
        if inRange(today) {
            let t = loc.t("aujourd'hui", "today")
            raws.append(Raw(x: x(today, px), w: CGFloat(t.count) * 6 + 16, text: t,
                            color: Theme.dawn, icon: "", filled: true))
        }
        for (h, end) in horizonEnds where inRange(end) {
            let t = h.label(loc.lang)
            raws.append(Raw(x: x(end, px), w: CGFloat(t.count) * 6 + 24, text: t,
                            color: Theme.accent(h), icon: "diamond.fill", filled: false))
        }
        raws.sort { $0.x < $1.x }
        var rowRight: [CGFloat] = []
        return raws.map { r in
            var row = rowRight.firstIndex { r.x >= $0 + 4 } ?? -1
            if row == -1 { rowRight.append(r.x + r.w); row = rowRight.count - 1 }
            else { rowRight[row] = r.x + r.w }
            return Marker(x: r.x, w: r.w, text: r.text, color: r.color, icon: r.icon, filled: r.filled, row: row)
        }
    }

    // MARK: Body

    var body: some View {
        GeometryReader { geo in
            let px = pxPerDay(geo.size.width)
            let markers = markerLayout(px)
            let bandRows = (markers.map(\.row).max() ?? -1) + 1
            let headerH = axisH + (bandRows > 0 ? CGFloat(bandRows) * markerRowH + 6 : 0)
            let (placements, laneSubs) = layout(px)
            let H = totalH(laneSubs, headerH)
            let stride = labelStride(px)
            // Lane labels stay pinned on the left; only the dated canvas scrolls
            // sideways. Vertical scroll handles the rare case where many
            // overlapping milestones grow the lanes taller than the window.
            verticalScrollIfNeeded(H, geo.size.height) {
                ScrollView(.horizontal, showsIndicators: true) {
                    canvas(placements, laneSubs, H, px, stride, headerH, markers, labelW)
                        .frame(width: labelW + contentW(px), height: H, alignment: .topLeading)
                }
                .frame(height: H)
                .overlay(alignment: .topLeading) {
                    laneLabelOverlay(laneSubs, headerH).frame(width: labelW, height: H)
                }
                .padding(.horizontal, hPad)
                .padding(.bottom, 18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .simultaneousGesture(
                MagnificationGesture()
                    .updating($pinch) { value, state, _ in state = value }
                    .onEnded { value in zoom = min(Self.maxZoom, max(1, zoom * value)) }
            )
        }
    }

    /// Add a vertical scroll only when the lanes are taller than the window —
    /// avoids the orthogonal-scroll nesting (which mis-measures height) in the
    /// common case where everything already fits.
    @ViewBuilder
    private func verticalScrollIfNeeded<Content: View>(_ contentH: CGFloat, _ available: CGFloat,
                                                       @ViewBuilder _ content: () -> Content) -> some View {
        if contentH + 24 > available {
            ScrollView(.vertical, showsIndicators: false) { content() }
        } else {
            content()
        }
    }

    // MARK: Pinned lane labels (frozen leading column, drawn in canvas coordinates)

    private func laneLabelOverlay(_ subs: [Int], _ headerH: CGFloat) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: headerH)
            ForEach(Array(lanes.enumerated()), id: \.offset) { li, h in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Circle().fill(Theme.accent(h)).frame(width: 7, height: 7)
                        Text(h.label(loc.lang)).font(Theme.display(13)).foregroundStyle(.white)
                    }
                    let count = intention.milestones(at: h).count
                    Text("\(count) " + loc.t("jalon" + (count == 1 ? "" : "s"),
                                             "milestone" + (count == 1 ? "" : "s")))
                        .font(Theme.body(9.5)).foregroundStyle(.white.opacity(0.45))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .frame(height: laneHeight(subs[li]))
                .padding(.leading, 4)
            }
        }
        // Opaque enough to mask the dated content that scrolls under it when zoomed.
        .background(Theme.nightDeep.opacity(0.9))
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.line.opacity(0.12)).frame(width: 1) }
    }

    // MARK: Canvas

    private func canvas(_ placements: [Placed], _ subs: [Int], _ H: CGFloat,
                        _ px: CGFloat, _ stride: Int, _ headerH: CGFloat,
                        _ markers: [Marker], _ inset: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            // Sizing spacer: pins the canvas to exactly (width × H) anchored top-left,
            // so `.frame(height: H)` can't vertically centre (and thus drift) the
            // offset-positioned content below the natural height of its tallest child.
            Color.clear.frame(width: inset + contentW(px), height: H)
            // Lane bands (zebra) span the full width, including under the labels.
            ForEach(Array(lanes.enumerated()), id: \.offset) { li, _ in
                Rectangle().fill(li % 2 == 0 ? Color.white.opacity(0.035) : Color.clear)
                    .frame(width: inset + contentW(px), height: laneHeight(subs[li]))
                    .offset(y: laneOriginY(li, subs, headerH))
            }
            // The dated layer, shifted right past the frozen label gutter so labels
            // and timeline share one coordinate space (no drift) yet never overlap.
            ZStack(alignment: .topLeading) {
                // Month gridlines + axis labels, thinned to `stride` when zoomed out.
                ForEach(Array(months.enumerated()), id: \.offset) { idx, d in
                    if idx % stride == 0 || cal.component(.month, from: d) == 1 {
                        gridline(d, H, px)
                        axisLabel(d, px)
                    }
                }
                // Horizon-close / today / anchor vertical lines.
                ForEach(Array(horizonEnds.enumerated()), id: \.offset) { _, pair in horizonLine(pair.0, pair.1, H, px) }
                todayLine(H, px)
                anchorLine(H, px)
                // Packed marker labels in the header band.
                ForEach(markers) { markerLabel($0, px) }
                // Milestone pills.
                ForEach(placements) { pill($0, subs, headerH, px) }
            }
            .offset(x: inset)
        }
    }

    private func markerLabel(_ m: Marker, _ px: CGFloat) -> some View {
        let cw = contentW(px)
        return HStack(spacing: 3) {
            if !m.icon.isEmpty { Image(systemName: m.icon).font(.system(size: 6)) }
            Text(m.text).font(Theme.mono(8.5))
        }
        .foregroundStyle(m.filled ? Theme.nightDeep : m.color)
        .padding(.horizontal, 5).padding(.vertical, 2)
        .background(Capsule().fill(m.filled ? m.color : Theme.nightDeep.opacity(0.9)))
        .overlay { if !m.filled { Capsule().strokeBorder(m.color.opacity(0.45), lineWidth: 0.5) } }
        .fixedSize()
        .offset(x: min(max(0, m.x + 3), cw - m.w), y: axisH + 4 + CGFloat(m.row) * markerRowH)
    }

    @ViewBuilder private func gridline(_ d: Date, _ H: CGFloat, _ px: CGFloat) -> some View {
        let isJan = cal.component(.month, from: d) == 1
        Rectangle().fill(Theme.line.opacity(isJan ? 0.16 : 0.06))
            .frame(width: isJan ? 1.5 : 1, height: H - axisH)
            .offset(x: x(d, px), y: axisH)
    }

    private func axisLabel(_ d: Date, _ px: CGFloat) -> some View {
        let isJan = cal.component(.month, from: d) == 1
        let df = DateFormatter(); df.locale = Locale(identifier: loc.lang == .fr ? "fr_CA" : "en_CA")
        df.setLocalizedDateFormatFromTemplate("MMM")
        return VStack(alignment: .leading, spacing: 1) {
            if isJan {
                Text(verbatim: "\(cal.component(.year, from: d))")
                    .font(Theme.mono(11)).foregroundStyle(.white.opacity(0.8))
            }
            Text(df.string(from: d).capitalized)
                .font(Theme.mono(9)).foregroundStyle(.white.opacity(0.5))
        }
        .offset(x: x(d, px) + 4, y: 7)
    }

    @ViewBuilder private func horizonLine(_ h: Horizon, _ end: Date, _ H: CGFloat, _ px: CGFloat) -> some View {
        if inRange(end) {
            Rectangle().fill(Theme.accent(h).opacity(0.5))
                .frame(width: 1.5, height: H - axisH)
                .offset(x: x(end, px), y: axisH)
        }
    }

    @ViewBuilder private func todayLine(_ H: CGFloat, _ px: CGFloat) -> some View {
        if inRange(today) {
            Rectangle().fill(Theme.dawn).frame(width: 2, height: H - axisH)
                .offset(x: x(today, px), y: axisH)
        }
    }

    @ViewBuilder private func anchorLine(_ H: CGFloat, _ px: CGFloat) -> some View {
        let anchor = CalendarPlan.startOfDay(intention.anchorDate, cal)
        if inRange(anchor) {
            Rectangle().fill(Theme.dusk.opacity(0.7))
                .frame(width: 1.5, height: H - axisH)
                .offset(x: x(anchor, px), y: axisH)
        }
    }

    private func pill(_ p: Placed, _ subs: [Int], _ headerH: CGFloat, _ px: CGFloat) -> some View {
        let y = laneOriginY(p.lane, subs, headerH) + laneVPad / 2 + CGFloat(p.sub) * (chipH + subGap)
        // Keep the whole pill on-canvas; near the right edge it stops flush instead of clipping.
        let clampedX = min(max(0, p.x), contentW(px) - chipW - 4)
        return Button { onSelect(p.id) } label: {
            HStack(spacing: 5) {
                Circle().fill(Theme.statusColor(p.m.status)).frame(width: 6, height: 6)
                Text(p.m.title).font(Theme.body(10)).lineLimit(1).foregroundStyle(Theme.parchmentInk)
            }
            .padding(.leading, 8).padding(.trailing, 7)
            .frame(width: chipW, height: chipH, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.parchment))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(Theme.accent(p.m.horizon))
                    .frame(width: 3).padding(.vertical, 3).padding(.leading, 2)
            }
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(
                Theme.accent(p.m.horizon).opacity(0.85),
                style: StrokeStyle(lineWidth: 1.5, dash: p.m.targetDate == nil ? [3, 2] : [])))
        }
        .buttonStyle(.plain)
        .help(p.m.title + (p.m.targetDate == nil ? " — " + loc.t("date estimée", "estimated date") : ""))
        .offset(x: clampedX, y: y)
    }
}
