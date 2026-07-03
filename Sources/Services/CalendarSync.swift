import Foundation
import EventKit
import SwiftData

/// Mirrors milestone target dates into a dedicated "L'Horizon" calendar in the
/// system Calendar app, so the plan lives where the user's days do. Each synced
/// milestone remembers its `EKEvent` identifier, so re-syncs update in place
/// rather than duplicating.
@MainActor
final class CalendarSync {
    static let shared = CalendarSync()

    private let store = EKEventStore()
    private let calendarTitle = "L'Horizon"

    enum SyncError: LocalizedError {
        case denied
        var errorDescription: String? {
            "Accès au calendrier refusé. Autorisez L'Horizon dans Réglages › Confidentialité."
        }
    }

    func requestAccess() async -> Bool {
        if #available(macOS 14.0, *) {
            return (try? await store.requestFullAccessToEvents()) ?? false
        } else {
            return (try? await store.requestAccess(to: .event)) ?? false
        }
    }

    /// Upsert an all-day event for every milestone with a target date; remove the
    /// event for any whose target was cleared. Returns the number of live events.
    @discardableResult
    func sync(intention: Intention, context: ModelContext, lang: Lang) async throws -> Int {
        guard await requestAccess() else { throw SyncError.denied }
        let calendar = try horizonCalendar()
        var count = 0
        for m in intention.allMilestones {
            guard let target = m.targetDate else {
                removeEvent(for: m, commit: false)
                continue
            }
            let event = existingEvent(for: m) ?? {
                let e = EKEvent(eventStore: store); e.calendar = calendar; return e
            }()
            let draft = CalendarSync.draft(title: m.title, dod: m.definitionOfDone,
                                           intentionTitle: intention.title, horizon: m.horizon, lang: lang)
            event.title = draft.title
            event.notes = draft.notes
            event.isAllDay = true
            event.startDate = Calendar.horizon.startOfDay(for: target)
            event.endDate = event.startDate
            event.calendar = calendar
            try store.save(event, span: .thisEvent, commit: false)
            m.calendarEventID = event.eventIdentifier
            count += 1
        }
        try store.commit()
        try? context.save()
        return count
    }

    /// Remove a single event by identifier (e.g. when a synced milestone is deleted).
    func removeEvent(id: String?) async {
        guard let id, await requestAccess(), let event = store.event(withIdentifier: id) else { return }
        try? store.remove(event, span: .thisEvent, commit: true)
    }

    /// Remove every event this intention created and forget their ids.
    func removeAll(for intention: Intention, context: ModelContext) async {
        guard await requestAccess() else { return }
        for m in intention.allMilestones { removeEvent(for: m, commit: false) }
        try? store.commit()
        try? context.save()
    }

    // MARK: Helpers

    private func existingEvent(for m: Milestone) -> EKEvent? {
        guard let id = m.calendarEventID else { return nil }
        return store.event(withIdentifier: id)
    }

    private func removeEvent(for m: Milestone, commit: Bool) {
        if let id = m.calendarEventID, let event = store.event(withIdentifier: id) {
            try? store.remove(event, span: .thisEvent, commit: commit)
        }
        m.calendarEventID = nil
    }

    private func horizonCalendar() throws -> EKCalendar {
        if let existing = store.calendars(for: .event).first(where: { $0.title == calendarTitle }) {
            return existing
        }
        let cal = EKCalendar(for: .event, eventStore: store)
        cal.title = calendarTitle
        cal.source = store.defaultCalendarForNewEvents?.source
            ?? store.sources.first(where: { $0.sourceType == .local })
            ?? store.sources.first
        try store.saveCalendar(cal, commit: true)
        return cal
    }

    // MARK: Pure event mapping (unit-tested)

    struct Draft: Equatable { let title: String; let notes: String }

    nonisolated static func draft(title: String, dod: String, intentionTitle: String,
                                  horizon: Horizon, lang: Lang) -> Draft {
        var notes = intentionTitle + " · " + horizon.label(lang)
        if !dod.isEmpty {
            notes += "\n" + (lang == .fr ? "Fait quand : " : "Done when: ") + dod
        }
        return Draft(title: "◇ " + title, notes: notes)
    }
}
