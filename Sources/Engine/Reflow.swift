import Foundation

/// A horizon-aware snapshot of a milestone for the pure re-flow planner. We work
/// on plain value types so the planner can be unit-tested without SwiftData.
struct PlanItem: Equatable, Identifiable {
    var id: UUID
    var title: String
    var horizon: Horizon
    var status: MilestoneStatus
    var progress: Double      // 0…1
}

/// Why the planner made a change — a language-neutral reason that the UI
/// localizes (FR-first). Keeping this an enum (not a baked string) means the
/// rationale honours the in-app FR/EN toggle.
enum RationaleKind: Equatable {
    case kept                 // done — left as is
    case slippedPushed(Horizon)   // slipped at nearest → pushed to a longer horizon
    case slippedRelaunched    // slipped at nearest with nowhere to push → relaunched
    case slippedActivated     // slipped further out → activated in place
    case missedTarget         // deadline passed → marked slipped
    case nearActivated        // nearest-lane planned → activated for the quarter
    case onTrack              // unchanged

    func text(_ lang: Lang) -> String {
        switch self {
        case .kept:
            return lang == .fr ? "Atteint — conservé." : "Achieved — kept."
        case .slippedPushed(let h):
            return lang == .fr
                ? "Glissé au plus proche → reporté à \(h.months) mois, à replanifier."
                : "Slipped at the nearest lane → pushed to \(h.months) mo, to re-plan."
        case .slippedRelaunched:
            return lang == .fr ? "Glissé — relancé en cours." : "Slipped — relaunched as active."
        case .slippedActivated:
            return lang == .fr ? "Glissé — ramené en cours dans son horizon."
                               : "Slipped — brought back as active in its horizon."
        case .missedTarget:
            return lang == .fr ? "Échéance dépassée — marqué glissé."
                               : "Deadline passed — marked slipped."
        case .nearActivated:
            return lang == .fr ? "Horizon proche — activé pour le trimestre."
                               : "Near horizon — activated for the quarter."
        case .onTrack:
            return lang == .fr ? "Sur la bonne voie." : "On track."
        }
    }
}

/// One proposed change the re-flow produced for a single item.
struct ReflowChange: Equatable, Identifiable {
    var id: UUID                       // the milestone id
    var title: String
    var fromHorizon: Horizon
    var toHorizon: Horizon
    var fromStatus: MilestoneStatus
    var toStatus: MilestoneStatus
    var kind: RationaleKind

    var movedHorizon: Bool { fromHorizon != toHorizon }
    var changedStatus: Bool { fromStatus != toStatus }
    var isNoOp: Bool { !movedHorizon && !changedStatus }
}

/// The deterministic re-flow planner. Given the current plan it decides, for
/// each item, where it should now live and what its status should be — the
/// non-AI baseline of the review ritual (the AI re-flow refines the wording and
/// can override, but the math here is what keeps the cascade honest).
///
/// Rules, applied per item:
///  - `done` → leave as is (no change).
///  - `slipped` at the nearest horizon → push to the next-longer horizon and
///    reset to `planned` (it didn't happen; give it more runway).
///  - `slipped` elsewhere → keep its horizon but pull intent forward by marking
///    `active` (commit to it this cycle) — unless it's already overdue twice.
///  - `planned`/`active` with the window now closed (target date passed) →
///    mark `slipped`.
///  - otherwise → unchanged.
enum Reflow {

    /// Re-plan `items` as of `now`, measuring horizon windows from `anchor`.
    /// `targetDates` optionally supplies an explicit target per item id; when a
    /// target is present and `< now`, the item is considered to have missed its
    /// window.
    static func plan(items: [PlanItem], anchor: Date, now: Date,
                     targetDates: [UUID: Date] = [:],
                     calendar: Calendar = .horizon) -> [ReflowChange] {
        items.map { item in
            var toHorizon = item.horizon
            var toStatus = item.status
            var kind: RationaleKind = .onTrack

            switch item.status {
            case .done:
                kind = .kept

            case .slipped:
                if item.horizon == .threeMonths {
                    // Nearest lane: there is nowhere shorter to pull it, so give
                    // it runway by pushing to the next horizon and re-planning.
                    if let longer = item.horizon.longer {
                        toHorizon = longer
                        toStatus = .planned
                        kind = .slippedPushed(longer)
                    } else {
                        toStatus = .active
                        kind = .slippedRelaunched
                    }
                } else {
                    // Further out: commit to it now by activating it in place.
                    toStatus = .active
                    kind = .slippedActivated
                }

            case .planned, .active:
                // Did its explicit window close?
                let missed = targetDates[item.id].map { $0 < now } ?? false
                if missed && item.progress < 1 {
                    toStatus = .slipped
                    kind = .missedTarget
                } else if item.status == .planned && item.horizon == .threeMonths {
                    // The nearest lane should be in motion.
                    toStatus = .active
                    kind = .nearActivated
                } else {
                    kind = .onTrack
                }
            }

            return ReflowChange(id: item.id, title: item.title,
                                fromHorizon: item.horizon, toHorizon: toHorizon,
                                fromStatus: item.status, toStatus: toStatus,
                                kind: kind)
        }
    }

    /// Convenience counts for a review summary.
    static func tally(_ changes: [ReflowChange]) -> (advanced: Int, slipped: Int, moved: Int) {
        var advanced = 0, slipped = 0, moved = 0
        for c in changes {
            if c.toStatus == .done || (c.fromStatus == .planned && c.toStatus == .active) { advanced += 1 }
            if c.toStatus == .slipped && c.fromStatus != .slipped { slipped += 1 }
            if c.movedHorizon { moved += 1 }
        }
        return (advanced, slipped, moved)
    }
}

/// Cascade ordering helpers used by the board and tested directly.
enum Cascade {
    /// Order items near→far (nearest horizon first; ties broken by progress
    /// descending so the most-advanced milestone leads its lane).
    static func ordered(_ items: [PlanItem]) -> [PlanItem] {
        items.sorted { a, b in
            if a.horizon != b.horizon { return a.horizon < b.horizon }
            return a.progress > b.progress
        }
    }

    /// Group items by horizon, returning the five lanes in cascade order
    /// (always all five keys, even if empty).
    static func lanes(_ items: [PlanItem]) -> [(Horizon, [PlanItem])] {
        Horizon.cascade.map { h in
            (h, items.filter { $0.horizon == h }.sorted { $0.progress > $1.progress })
        }
    }

    /// Whether a cascade is "well-formed": there is at least one milestone at the
    /// nearest horizon when any further horizon is populated (you should always
    /// have a next concrete step).
    static func hasNearTermAnchor(_ items: [PlanItem]) -> Bool {
        guard items.contains(where: { $0.horizon != .threeMonths }) else { return true }
        return items.contains { $0.horizon == .threeMonths }
    }
}
