import SwiftUI
import SwiftData

/// The review ritual. Pick a cadence, mark progress/slips on each milestone,
/// run the deterministic re-flow (always available) and optionally the AI
/// re-flow (with a key), then commit the review to the log.
struct ReviewView: View {
    @EnvironmentObject var loc: LocManager
    @Environment(\.modelContext) private var context
    @Bindable var intention: Intention

    @State private var cadence: ReviewCadence = .weekly
    @State private var changes: [ReflowChange] = []
    @State private var aiSummary = ""
    @State private var aiSuggestions: [ReflowSuggestion] = []
    @State private var focusPoints: [String] = []
    @State private var loading = false
    @State private var error: String?
    @State private var committed = false
    private let hasKey = OpusClient.hasKey

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                progressGrid
                reflowSection
                logSection
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
            .frame(maxWidth: 880).frame(maxWidth: .infinity)
        }
        .onAppear { cadence = intention.reviewCadence }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(loc.t("Revue", "Review")).font(Theme.display(26)).foregroundStyle(.white)
            Text(loc.t("Marquez ce qui a avancé, ce qui a glissé. Puis on replanifie.",
                       "Mark what advanced, what slipped. Then we re-flow."))
                .font(Theme.body(13)).foregroundStyle(.white.opacity(0.7))
            Picker("", selection: $cadence) {
                ForEach(ReviewCadence.allCases) { c in Text(c.label(loc.lang)).tag(c) }
            }
            .pickerStyle(.segmented).frame(width: 320).padding(.top, 4)
        }
    }

    /// Quick mark-up grid: each milestone with a status cycler and progress.
    private var progressGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(loc.t("État courant", "Current state")).font(Theme.display(16)).foregroundStyle(.white)
            ForEach(Horizon.cascade) { h in
                let items = intention.milestones(at: h)
                if !items.isEmpty {
                    ForEach(items) { ms in reviewRow(ms, h) }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.05)))
    }

    private func reviewRow(_ ms: Milestone, _ h: Horizon) -> some View {
        HStack(spacing: 10) {
            Circle().fill(Theme.accent(h)).frame(width: 7, height: 7)
            Text(ms.title).font(Theme.body(13)).foregroundStyle(.white).lineLimit(1)
            Spacer()
            Text(h.label(loc.lang)).font(Theme.mono(10)).foregroundStyle(.white.opacity(0.5))
            Menu {
                ForEach(MilestoneStatus.allCases) { s in
                    Button(s.label(loc.lang)) { ms.status = s; try? context.save() }
                }
            } label: {
                HStack(spacing: 4) {
                    Circle().fill(Theme.statusColor(ms.status)).frame(width: 7, height: 7)
                    Text(ms.status.label(loc.lang)).font(Theme.body(11))
                }
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.08)))
                .foregroundStyle(.white)
            }
            .menuStyle(.borderlessButton).fixedSize()
            HorizonRing(progress: ms.progress, color: Theme.accent(h), lineWidth: 3.5, size: 26)
        }
        .padding(.vertical, 3)
    }

    private var reflowSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(loc.t("Re-flow", "Re-flow")).font(Theme.display(16)).foregroundStyle(.white)
                Spacer()
                Button { computeDeterministic() } label: {
                    Label(loc.t("Replanifier", "Re-plan"), systemImage: "arrow.triangle.2.circlepath")
                        .font(Theme.body(12))
                }
                .buttonStyle(.bordered).tint(Theme.dawnSoft)
                Button { Task { await runCheckIn() } } label: {
                    Label(loc.t("Bilan IA", "AI check-in"), systemImage: "text.badge.checkmark")
                        .font(Theme.body(12))
                }
                .buttonStyle(.bordered).tint(Theme.dawnSoft).disabled(!hasKey || loading)
                Button { Task { await runAI() } } label: {
                    Label(loc.t("Re-flow IA", "AI re-flow"), systemImage: "sparkles").font(Theme.body(12))
                }
                .buttonStyle(.borderedProminent).tint(Theme.dawn).disabled(!hasKey || loading)
            }
            if !hasKey {
                Text(loc.t("Ajoutez une clé dans ~/.horizon/config pour le re-flow IA. Le re-flow automatique reste disponible.",
                           "Add a key in ~/.horizon/config for AI re-flow. Automatic re-flow stays available."))
                    .font(Theme.body(11)).foregroundStyle(.white.opacity(0.55))
            }
            if loading {
                HStack { ProgressView().controlSize(.small).tint(.white)
                    Text(loc.t("Le cartographe redessine…", "Redrawing the map…"))
                        .font(Theme.body(12)).foregroundStyle(.white.opacity(0.7)) }
            }
            if let error {
                Text(error).font(Theme.body(11)).foregroundStyle(Theme.statusColor(.slipped))
            }
            if !aiSummary.isEmpty {
                Text(aiSummary).font(Theme.displayLight(14)).italic().foregroundStyle(Theme.dawnSoft)
                    .padding(.vertical, 4)
            }
            if !focusPoints.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(loc.t("Cette semaine", "This week"))
                        .font(Theme.body(11)).foregroundStyle(.white.opacity(0.55))
                    ForEach(focusPoints, id: \.self) { p in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "arrow.right").font(.system(size: 9)).foregroundStyle(Theme.dawn)
                            Text(p).font(Theme.body(12)).foregroundStyle(.white.opacity(0.85))
                        }
                    }
                }
                .padding(.bottom, 2)
            }
            ForEach(changes.filter { !$0.isNoOp }) { c in changeRow(c) }
            ForEach(aiSuggestions) { s in suggestionRow(s) }
            if !changes.isEmpty || !aiSuggestions.isEmpty || !aiSummary.isEmpty || !focusPoints.isEmpty {
                HStack {
                    Spacer()
                    Button { applyAndCommit() } label: {
                        Label(committed ? loc.t("Revue consignée", "Review logged")
                                        : loc.t("Appliquer & consigner", "Apply & log"),
                              systemImage: committed ? "checkmark.seal.fill" : "checkmark.seal")
                    }
                    .buttonStyle(.borderedProminent).tint(committed ? Theme.statusColor(.done) : Theme.dawn)
                    .disabled(committed)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.05)))
    }

    private func changeRow(_ c: ReflowChange) -> some View {
        HStack(spacing: 10) {
            Image(systemName: c.movedHorizon ? "arrow.right" : "arrow.up")
                .foregroundStyle(Theme.dawnSoft).font(.system(size: 11))
            VStack(alignment: .leading, spacing: 2) {
                Text(c.title).font(Theme.body(12.5)).foregroundStyle(.white)
                HStack(spacing: 6) {
                    if c.movedHorizon {
                        Text(c.fromHorizon.label(loc.lang) + " → " + c.toHorizon.label(loc.lang))
                            .font(Theme.mono(10)).foregroundStyle(Theme.dawnSoft)
                    }
                    if c.changedStatus {
                        Text(c.fromStatus.label(loc.lang) + " → " + c.toStatus.label(loc.lang))
                            .font(Theme.mono(10)).foregroundStyle(Theme.statusColor(c.toStatus))
                    }
                }
                Text(c.kind.text(loc.lang)).font(Theme.body(10.5)).foregroundStyle(.white.opacity(0.55))
            }
            Spacer()
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 9).fill(.white.opacity(0.04)))
    }

    private func suggestionRow(_ s: ReflowSuggestion) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles").foregroundStyle(Theme.dawn).font(.system(size: 11))
            VStack(alignment: .leading, spacing: 2) {
                Text(s.milestoneTitle).font(Theme.body(12.5)).foregroundStyle(.white)
                if let h = s.suggestedHorizon {
                    Text(loc.t("→ vers ", "→ to ") + h.label(loc.lang))
                        .font(Theme.mono(10)).foregroundStyle(Theme.dawnSoft)
                }
                Text(s.note).font(Theme.body(10.5)).foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.dawn.opacity(0.08)))
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(loc.t("Journal des revues", "Review log")).font(Theme.display(16)).foregroundStyle(.white)
            if intention.allReviews.isEmpty {
                Text(loc.t("Aucune revue encore.", "No reviews yet."))
                    .font(Theme.body(12)).italic().foregroundStyle(.white.opacity(0.4))
            } else {
                ForEach(intention.allReviews) { r in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(r.date.formatted(date: .abbreviated, time: .omitted))
                                .font(Theme.mono(11)).foregroundStyle(.white.opacity(0.6))
                            Text("· " + r.cadence.label(loc.lang))
                                .font(Theme.body(10.5)).foregroundStyle(.white.opacity(0.5))
                            Spacer()
                            Text("↑\(r.advancedCount)  ↓\(r.slippedCount)")
                                .font(Theme.mono(10)).foregroundStyle(.white.opacity(0.5))
                        }
                        if !r.summary.isEmpty {
                            Text(r.summary).font(Theme.body(12)).foregroundStyle(.white.opacity(0.82))
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 9).fill(.white.opacity(0.04)))
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.05)))
    }

    // MARK: Actions

    private func snapshotItems() -> [PlanItem] {
        intention.allMilestones.map {
            PlanItem(id: $0.id, title: $0.title, horizon: $0.horizon,
                     status: $0.status, progress: $0.progress)
        }
    }

    private func computeDeterministic() {
        committed = false
        let items = snapshotItems()
        let targets = Dictionary(uniqueKeysWithValues:
            intention.allMilestones.compactMap { m in m.targetDate.map { (m.id, $0) } })
        changes = Reflow.plan(items: items, anchor: intention.anchorDate, now: Date(),
                              targetDates: targets)
    }

    private func runAI() async {
        committed = false
        computeDeterministic()
        loading = true; error = nil
        let snapshot = buildSnapshotText()
        do {
            let r = try await HorizonAI.reflow(intentionTitle: intention.title,
                                               snapshot: snapshot, lang: loc.lang)
            aiSummary = r.summary; aiSuggestions = r.suggestions
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    /// A narrative weekly check-in (progress + risk + this week's focus actions).
    private func runCheckIn() async {
        committed = false
        loading = true; error = nil
        do {
            let r = try await HorizonAI.checkIn(intentionTitle: intention.title,
                                                snapshot: buildSnapshotText(), lang: loc.lang)
            aiSummary = r.summary; focusPoints = r.focus
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func buildSnapshotText() -> String {
        var lines: [String] = []
        for h in Horizon.cascade {
            for m in intention.milestones(at: h) {
                lines.append("- [\(h.label(.fr))] \(m.title) — \(m.status.label(.fr)), \(Int(m.progress * 100))%")
            }
        }
        var s = "Jalons actuels :\n" + lines.joined(separator: "\n")
        let det = changes.filter { !$0.isNoOp }.map { "• \($0.title): \($0.kind.text(.fr))" }
        if !det.isEmpty { s += "\n\nProposition automatique :\n" + det.joined(separator: "\n") }
        return s
    }

    /// Apply the deterministic re-flow to the real models + write a ReviewLog.
    private func applyAndCommit() {
        if changes.isEmpty { computeDeterministic() }
        for c in changes where !c.isNoOp {
            if let m = intention.allMilestones.first(where: { $0.id == c.id }) {
                m.horizon = c.toHorizon
                m.status = c.toStatus
            }
        }
        // Apply AI horizon suggestions where a title matches.
        for s in aiSuggestions {
            if let h = s.suggestedHorizon,
               let m = intention.allMilestones.first(where: { $0.title == s.milestoneTitle }) {
                m.horizon = h
            }
        }
        let tally = Reflow.tally(changes)
        let notes = aiSuggestions.map(\.note) + focusPoints
        let log = ReviewLog(date: Date(), cadence: cadence,
                            summary: aiSummary.isEmpty
                                ? loc.t("Revue \(cadence.label(.fr)) : \(tally.advanced) avancés, \(tally.slipped) glissés, \(tally.moved) déplacés.",
                                        "\(cadence.label(.en)) review: \(tally.advanced) advanced, \(tally.slipped) slipped, \(tally.moved) moved.")
                                : aiSummary,
                            advancedCount: tally.advanced, slippedCount: tally.slipped,
                            reflowNote: notes.joined(separator: " · "))
        log.intention = intention
        context.insert(log)
        // Persist the chosen cadence and refresh the review reminders.
        intention.reviewCadence = cadence
        try? context.save()
        let all = (try? context.fetch(FetchDescriptor<Intention>())) ?? []
        Task { await NotificationManager.shared.rescheduleReviewReminders(all, lang: loc.lang) }
        committed = true
    }
}
