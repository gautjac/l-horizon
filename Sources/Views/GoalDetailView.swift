import SwiftUI
import SwiftData

/// The single-intention milestone tree, editable. Grouped by horizon in cascade
/// order, each milestone expandable to its steps; add/edit/delete inline.
struct GoalDetailView: View {
    @EnvironmentObject var loc: LocManager
    @Environment(\.modelContext) private var context
    @Bindable var intention: Intention

    @State private var editingIntention = false
    @State private var newMilestoneHorizon: Horizon?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                intentionHeader
                ForEach(Horizon.cascade) { h in
                    horizonSection(h)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .frame(maxWidth: 880, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $editingIntention) {
            IntentionEditor(intention: intention)
        }
        .sheet(item: $newMilestoneHorizon) { h in
            MilestoneEditor(milestone: nil, intention: intention, horizon: h)
        }
    }

    private var intentionHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(intention.title)
                        .font(Theme.display(26)).foregroundStyle(.white)
                    if !intention.detail.isEmpty {
                        Text(intention.detail)
                            .font(Theme.body(13)).foregroundStyle(.white.opacity(0.72))
                    }
                }
                Spacer()
                HorizonRing(progress: intention.progress,
                            color: Theme.dawn, lineWidth: 6, size: 56)
                Button { editingIntention = true } label: {
                    Image(systemName: "pencil").foregroundStyle(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 6) {
                Image(systemName: "calendar").font(.system(size: 10))
                Text(loc.t("ancré le ", "anchored ") +
                     intention.anchorDate.formatted(date: .abbreviated, time: .omitted))
                Text("·")
                Text(loc.t("sommet : ", "summit: ") + intention.topHorizon.label(loc.lang))
            }
            .font(Theme.body(11)).foregroundStyle(.white.opacity(0.5))
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func horizonSection(_ h: Horizon) -> some View {
        let items = intention.milestones(at: h)
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Circle().fill(Theme.accent(h)).frame(width: 10, height: 10)
                Text(h.label(loc.lang)).font(Theme.display(18)).foregroundStyle(.white)
                Text(h.phrase(loc.lang)).font(Theme.displayLight(12)).italic()
                    .foregroundStyle(.white.opacity(0.45))
                Spacer()
                Button { newMilestoneHorizon = h } label: {
                    Image(systemName: "plus.circle").foregroundStyle(Theme.accent(h))
                }
                .buttonStyle(.plain)
                .help(loc.t("Ajouter un jalon", "Add a milestone"))
            }
            if items.isEmpty {
                Text(loc.t("Aucun jalon à cet horizon.", "No milestones at this horizon."))
                    .font(Theme.body(12)).italic().foregroundStyle(.white.opacity(0.4))
                    .padding(.leading, 18)
            } else {
                ForEach(items) { ms in
                    MilestoneDetailRow(milestone: ms)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.05)))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Theme.accent(h).opacity(0.25), lineWidth: 1))
    }
}

/// An expandable milestone row inside the detail tree.
struct MilestoneDetailRow: View {
    @EnvironmentObject var loc: LocManager
    @Environment(\.modelContext) private var context
    @Bindable var milestone: Milestone
    @State private var expanded = false
    @State private var editing = false
    @State private var newStepText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Button { cycleStatus() } label: {
                    Image(systemName: statusIcon)
                        .foregroundStyle(Theme.statusColor(milestone.status))
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .help(loc.t("Changer le statut", "Cycle status"))

                VStack(alignment: .leading, spacing: 2) {
                    Text(milestone.title).font(Theme.body(14.5)).foregroundStyle(.white)
                    if !milestone.definitionOfDone.isEmpty {
                        Text(loc.t("fait quand : ", "done when: ") + milestone.definitionOfDone)
                            .font(Theme.body(10.5)).foregroundStyle(.white.opacity(0.55))
                    }
                }
                Spacer()
                HorizonRing(progress: milestone.progress,
                            color: Theme.accent(milestone.horizon), lineWidth: 4, size: 30)
                Button { withAnimation { expanded.toggle() } } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .foregroundStyle(.white.opacity(0.5)).font(.system(size: 11))
                }
                .buttonStyle(.plain)
            }
            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(milestone.allSteps) { step in
                        StepRow(step: step) { try? context.save() }
                    }
                    HStack {
                        Image(systemName: "plus").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                        TextField(loc.t("Ajouter une étape…", "Add a step…"), text: $newStepText)
                            .textFieldStyle(.plain).font(Theme.body(12))
                            .foregroundStyle(.white)
                            .onSubmit(addStep)
                    }
                    HStack(spacing: 12) {
                        Button { editing = true } label: {
                            Label(loc.t("Modifier", "Edit"), systemImage: "pencil").font(Theme.body(11))
                        }.buttonStyle(.plain).foregroundStyle(Theme.dawnSoft)
                        Button(role: .destructive) { delete() } label: {
                            Label(loc.t("Supprimer", "Delete"), systemImage: "trash").font(Theme.body(11))
                        }.buttonStyle(.plain).foregroundStyle(Theme.statusColor(.slipped))
                    }
                    .padding(.top, 2)
                }
                .padding(.leading, 26).padding(.top, 4)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 9).fill(.white.opacity(0.03)))
        .sheet(isPresented: $editing) {
            MilestoneEditor(milestone: milestone)
        }
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

    private func addStep() {
        let text = newStepText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let step = Step(text: text, sortIndex: (milestone.allSteps.map(\.sortIndex).max() ?? -1) + 1)
        step.milestone = milestone
        context.insert(step)
        newStepText = ""
        try? context.save()
    }

    private func delete() {
        context.delete(milestone)
        try? context.save()
    }
}

struct StepRow: View {
    @Bindable var step: Step
    var onChange: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Button { step.isDone.toggle(); onChange() } label: {
                Image(systemName: step.isDone ? "checkmark.square.fill" : "square")
                    .foregroundStyle(step.isDone ? Theme.statusColor(.done) : .white.opacity(0.4))
            }
            .buttonStyle(.plain)
            Text(step.text)
                .font(Theme.body(12.5))
                .strikethrough(step.isDone, color: .white.opacity(0.4))
                .foregroundStyle(step.isDone ? .white.opacity(0.45) : .white.opacity(0.85))
            Spacer()
        }
    }
}
