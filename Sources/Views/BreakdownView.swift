import SwiftUI
import SwiftData

/// The AI milestone-breakdown sheet. Given the intention (+ optional extra
/// context), it asks Claude to propose a full cascade, previews the proposals,
/// and lets the user accept them (which inserts real Milestones + Steps).
struct BreakdownView: View {
    @EnvironmentObject var loc: LocManager
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var intention: Intention

    @State private var extraContext = ""
    @State private var proposals: [ProposedMilestone] = []
    @State private var accepted: Set<UUID> = []
    @State private var loading = false
    @State private var error: String?
    private let hasKey = OpusClient.hasKey

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !hasKey {
                keyNote
            }
            if proposals.isEmpty {
                inputArea
            } else {
                proposalList
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(24)
        .frame(width: 620, height: 620)
        .background(Theme.sky)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(loc.t("Décomposer avec l'IA", "Break down with AI"), systemImage: "sparkles")
                .font(Theme.display(22)).foregroundStyle(.white)
            Text(intention.title).font(Theme.body(13)).foregroundStyle(.white.opacity(0.7))
        }
        .padding(.bottom, 14)
    }

    private var keyNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "key").foregroundStyle(Theme.dawnSoft)
            VStack(alignment: .leading, spacing: 2) {
                Text(loc.t("Ajoutez votre clé", "Add your key")).font(Theme.body(13)).bold()
                    .foregroundStyle(.white)
                Text(loc.t("Placez votre clé Anthropic dans ~/.horizon/config (ou la variable CLAUDE_API_KEY) pour activer l'IA. La planification manuelle fonctionne sans clé.",
                           "Put your Anthropic key in ~/.horizon/config (or the CLAUDE_API_KEY env var) to enable AI. Manual planning works without a key."))
                    .font(Theme.body(11)).foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 11).fill(.white.opacity(0.07)))
        .padding(.bottom, 12)
    }

    private var inputArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(loc.t("Contexte supplémentaire (optionnel)", "Extra context (optional)"))
                .font(Theme.body(12)).foregroundStyle(.white.opacity(0.7))
            TextEditor(text: $extraContext)
                .font(Theme.body(13)).scrollContentBackground(.hidden)
                .padding(8).frame(height: 120)
                .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.08)))
                .foregroundStyle(.white)
            if let error {
                Text(error).font(Theme.body(11)).foregroundStyle(Theme.statusColor(.slipped))
            }
        }
    }

    private var proposalList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(loc.t("\(proposals.count) jalons proposés — cochez ceux à garder.",
                           "\(proposals.count) milestones proposed — check the ones to keep."))
                    .font(Theme.body(12)).foregroundStyle(.white.opacity(0.7))
                ForEach(Horizon.cascade) { h in
                    let group = proposals.filter { $0.horizon == h }
                    if !group.isEmpty {
                        HStack(spacing: 6) {
                            Circle().fill(Theme.accent(h)).frame(width: 8, height: 8)
                            Text(h.label(loc.lang)).font(Theme.display(15)).foregroundStyle(.white)
                        }
                        .padding(.top, 4)
                        ForEach(group) { p in proposalRow(p) }
                    }
                }
            }
        }
    }

    private func proposalRow(_ p: ProposedMilestone) -> some View {
        Button { toggle(p.id) } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: accepted.contains(p.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(accepted.contains(p.id) ? Theme.statusColor(.done) : .white.opacity(0.4))
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.title).font(Theme.body(13.5)).bold().foregroundStyle(.white)
                    if !p.definitionOfDone.isEmpty {
                        Text(loc.t("fait quand : ", "done when: ") + p.definitionOfDone)
                            .font(Theme.body(11)).foregroundStyle(.white.opacity(0.6))
                    }
                    if !p.steps.isEmpty {
                        Text(p.steps.joined(separator: " · "))
                            .font(Theme.body(10.5)).foregroundStyle(.white.opacity(0.45))
                    }
                }
                Spacer()
            }
            .padding(11)
            .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack {
            if loading {
                ProgressView().controlSize(.small).tint(.white)
                Text(loc.t("Le cartographe trace le chemin…", "The cartographer is charting the path…"))
                    .font(Theme.body(12)).foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            Button(loc.t("Fermer", "Close")) { dismiss() }.foregroundStyle(.white)
            if proposals.isEmpty {
                Button(loc.t("Proposer", "Propose")) { Task { await run() } }
                    .buttonStyle(.borderedProminent).tint(Theme.dawn)
                    .disabled(!hasKey || loading)
            } else {
                Button(loc.t("Ajouter \(accepted.count) jalons", "Add \(accepted.count) milestones")) { accept() }
                    .buttonStyle(.borderedProminent).tint(Theme.dawn)
                    .disabled(accepted.isEmpty)
            }
        }
        .padding(.top, 12)
    }

    private func toggle(_ id: UUID) {
        if accepted.contains(id) { accepted.remove(id) } else { accepted.insert(id) }
    }

    private func run() async {
        loading = true; error = nil
        do {
            let result = try await HorizonAI.breakdown(
                intention: intention.title, context: extraContext,
                topHorizon: intention.topHorizon, lang: loc.lang)
            proposals = result
            accepted = Set(result.map(\.id)) // pre-check all
            if result.isEmpty { error = loc.t("Aucune proposition.", "No proposals returned.") }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func accept() {
        for p in proposals where accepted.contains(p.id) {
            let m = Milestone(title: p.title, horizon: p.horizon,
                              definitionOfDone: p.definitionOfDone,
                              sortIndex: (intention.milestones(at: p.horizon).map(\.sortIndex).max() ?? -1) + 1)
            m.intention = intention
            context.insert(m)
            for (i, s) in p.steps.enumerated() {
                let step = Step(text: s, sortIndex: i)
                step.milestone = m
                context.insert(step)
            }
        }
        try? context.save()
        dismiss()
    }
}
