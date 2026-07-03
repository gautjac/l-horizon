import SwiftUI
import SwiftData

/// "Maintenant" — the cross-intention focus view. Instead of the long horizon
/// board, it answers "what do I actually do now": the milestones that are
/// slipped, active, due soon, or next up across every intention, plus any
/// intention that's due for its review.
struct FocusView: View {
    @EnvironmentObject var loc: LocManager
    @Environment(\.modelContext) private var context
    @Query(sort: \Intention.sortIndex) private var intentions: [Intention]
    /// Jump to an intention's Review tab.
    var onReview: (UUID) -> Void

    @State private var editTarget: EditID?
    private struct EditID: Identifiable { let id: UUID }

    private struct Row: Identifiable {
        let item: FocusItem; let milestone: Milestone; let intention: Intention
        var id: UUID { item.id }
    }

    private var dueForReview: [Intention] { intentions.filter { $0.isReviewDue() } }

    private var rows: [Row] {
        var lookup: [UUID: (Milestone, Intention)] = [:]
        var candidates: [FocusCandidate] = []
        for intention in intentions {
            for m in intention.allMilestones {
                let eff = CalendarPlan.effectiveDate(targetDate: m.targetDate, horizon: m.horizon,
                                                     anchor: intention.anchorDate)
                candidates.append(FocusCandidate(id: m.id, horizon: m.horizon, status: m.status,
                                                 effectiveDate: eff,
                                                 openSteps: m.allSteps.filter { !$0.isDone }.count))
                lookup[m.id] = (m, intention)
            }
        }
        return FocusEngine.select(candidates).compactMap { item in
            lookup[item.id].map { Row(item: item, milestone: $0.0, intention: $0.1) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if !dueForReview.isEmpty { reviewSection }
                focusSection
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
            .frame(maxWidth: 960, alignment: .leading).frame(maxWidth: .infinity)
        }
        .sheet(item: $editTarget) { target in
            if let m = milestone(target.id) { MilestoneEditor(milestone: m) }
        }
    }

    private func milestone(_ id: UUID) -> Milestone? {
        intentions.flatMap(\.allMilestones).first { $0.id == id }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(loc.t("Maintenant", "Now")).font(Theme.display(28)).foregroundStyle(.white)
            Text(loc.t("Ce qui mérite votre attention aujourd'hui, toutes intentions confondues.",
                       "What deserves your attention today, across every intention."))
                .font(Theme.displayLight(13)).italic().foregroundStyle(.white.opacity(0.6))
        }
    }

    // MARK: Reviews due

    private var reviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(loc.t("À réviser", "To review"), systemImage: "checkmark.seal")
                .font(Theme.display(16)).foregroundStyle(.white)
            ForEach(dueForReview) { intention in
                HStack(spacing: 10) {
                    Circle().fill(Theme.dawn).frame(width: 7, height: 7)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(intention.title).font(Theme.body(13.5)).foregroundStyle(.white).lineLimit(1)
                        Text(overdueLabel(intention))
                            .font(Theme.body(10.5)).foregroundStyle(.white.opacity(0.5))
                    }
                    Spacer()
                    Button { onReview(intention.id) } label: {
                        Label(loc.t("Réviser", "Review"), systemImage: "arrow.right").font(Theme.body(11.5))
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.dawn)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.dawn.opacity(0.08)))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.05)))
    }

    private func overdueLabel(_ intention: Intention) -> String {
        let days = -ReviewSchedule.daysUntilDue(lastReviewed: intention.lastReviewedAt,
                                                 cadence: intention.reviewCadence)
        let cad = intention.reviewCadence.label(loc.lang)
        if days <= 0 { return loc.t("revue \(cad) — dû aujourd'hui", "\(cad) review — due today") }
        return loc.t("revue \(cad) — en retard de \(days) j", "\(cad) review — \(days) d overdue")
    }

    // MARK: Focus list

    private var focusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(loc.t("En jeu cette semaine", "In play this week"), systemImage: "target")
                .font(Theme.display(16)).foregroundStyle(.white)
            if rows.isEmpty {
                Text(loc.t("Rien d'urgent. Le long terme peut respirer.",
                           "Nothing pressing. The long game can breathe."))
                    .font(Theme.body(12.5)).italic().foregroundStyle(.white.opacity(0.4))
                    .padding(.vertical, 6)
            } else {
                ForEach(rows) { row in
                    FocusRow(row.item, row.milestone, row.intention) { editTarget = EditID(id: row.id) }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.05)))
    }
}

/// One milestone in the focus list, with its intention, reason, and expandable steps.
private struct FocusRow: View {
    @EnvironmentObject var loc: LocManager
    @Environment(\.modelContext) private var context
    @Bindable var milestone: Milestone
    let item: FocusItem
    let intention: Intention
    let onOpen: () -> Void
    @State private var expanded = false

    init(_ item: FocusItem, _ milestone: Milestone, _ intention: Intention, onOpen: @escaping () -> Void) {
        self.item = item; self.milestone = milestone; self.intention = intention; self.onOpen = onOpen
    }

    private var reasonColor: Color {
        switch item.reason {
        case .slipped: return Theme.statusColor(.slipped)
        case .active:  return Theme.statusColor(.active)
        case .dueSoon: return Theme.dawn
        case .nearHorizon: return Theme.accent(.threeMonths)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button { cycleStatus() } label: {
                    Image(systemName: statusIcon).foregroundStyle(Theme.statusColor(milestone.status))
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain).help(loc.t("Changer le statut", "Cycle status"))

                VStack(alignment: .leading, spacing: 2) {
                    Button(action: onOpen) {
                        Text(milestone.title).font(Theme.body(14)).foregroundStyle(.white)
                            .lineLimit(1).multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                    HStack(spacing: 6) {
                        Text(intention.title).font(Theme.body(10.5)).foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                        Text("·").foregroundStyle(.white.opacity(0.3))
                        Text(milestone.horizon.label(loc.lang))
                            .font(Theme.mono(9.5)).foregroundStyle(Theme.accent(milestone.horizon))
                    }
                }
                Spacer()
                reasonChip
                if !milestone.allSteps.isEmpty {
                    Button { withAnimation { expanded.toggle() } } label: {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .foregroundStyle(.white.opacity(0.5)).font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
            }
            if expanded {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(milestone.allSteps) { step in
                        StepRow(step: step) { try? context.save() }
                    }
                }
                .padding(.leading, 26).padding(.top, 2)
            }
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.035)))
    }

    private var reasonChip: some View {
        Text(item.reason.label(loc.lang).uppercased())
            .font(Theme.mono(8.5)).tracking(0.4)
            .foregroundStyle(reasonColor)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(reasonColor.opacity(0.15)))
    }

    private var statusIcon: String {
        switch milestone.status {
        case .planned: return "circle"
        case .active:  return "circle.lefthalf.filled"
        case .done:    return "checkmark.circle.fill"
        case .slipped: return "exclamationmark.circle"
        }
    }

    private func cycleStatus() {
        let order: [MilestoneStatus] = [.planned, .active, .done, .slipped]
        let i = order.firstIndex(of: milestone.status) ?? 0
        milestone.status = order[(i + 1) % order.count]
        try? context.save()
    }
}
