import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// THE signature view: the five horizon lanes (3 mois → 5 ans) laid out as
/// receding bands over the dawn-to-night sky. Each lane holds its milestones;
/// drag a card to another lane to re-assign its horizon. A "décomposer avec
/// l'IA" action proposes the whole cascade.
struct HorizonBoardView: View {
    @EnvironmentObject var loc: LocManager
    @Environment(\.modelContext) private var context
    @Bindable var intention: Intention

    @State private var showBreakdown = false
    @State private var draggingID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(Horizon.cascade.enumerated()), id: \.element) { idx, h in
                        HorizonLane(intention: intention, horizon: h, index: idx,
                                    draggingID: $draggingID,
                                    onDrop: { mid in assign(mid, to: h) })
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 28)
            }
        }
        .sheet(isPresented: $showBreakdown) {
            BreakdownView(intention: intention)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(intention.title)
                    .font(Theme.display(24))
                    .foregroundStyle(.white)
                if !intention.detail.isEmpty {
                    Text(intention.detail)
                        .font(Theme.body(12.5))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(2)
                }
            }
            Spacer()
            seasonChip
            Button { showBreakdown = true } label: {
                Label(loc.t("Décomposer avec l'IA", "Break down with AI"), systemImage: "sparkles")
                    .font(Theme.body(13))
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.dawn)
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    /// "Ce qui s'en vient" — count of milestones due in the nearest horizon.
    private var seasonChip: some View {
        let near = intention.milestones(at: .threeMonths)
        let active = near.filter { $0.status == .active || $0.status == .planned }.count
        return VStack(spacing: 1) {
            Text("\(active)")
                .font(Theme.display(20)).foregroundStyle(Theme.dawnSoft)
            Text(loc.t("ce trimestre", "this quarter"))
                .font(Theme.body(9.5)).foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 11).fill(.white.opacity(0.06)))
        .padding(.trailing, 6)
    }

    private func assign(_ milestoneID: UUID, to horizon: Horizon) {
        guard let ms = intention.allMilestones.first(where: { $0.id == milestoneID }) else { return }
        guard ms.horizon != horizon else { return }
        ms.horizon = horizon
        let peers = intention.milestones(at: horizon)
        ms.sortIndex = (peers.map(\.sortIndex).max() ?? 0) + 1
        try? context.save()
    }
}

/// One horizon lane — its label rail, the receding-line backdrop, and its cards.
struct HorizonLane: View {
    @EnvironmentObject var loc: LocManager
    @Bindable var intention: Intention
    let horizon: Horizon
    let index: Int
    @Binding var draggingID: UUID?
    var onDrop: (UUID) -> Void

    @State private var targeted = false

    private var items: [Milestone] { intention.milestones(at: horizon) }

    /// Lane progress ring = mean of its milestones.
    private var laneProgress: Double {
        guard !items.isEmpty else { return 0 }
        return items.map(\.progress).reduce(0, +) / Double(items.count)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            rail
            cards
        }
        .padding(.vertical, 10)
        .background(alignment: .topLeading) {
            // Faint horizon line across the lane top — the cartographer motif.
            Rectangle()
                .fill(Theme.line.opacity(0.18 - Double(index) * 0.02))
                .frame(height: 1)
                .padding(.top, 2)
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(targeted ? Theme.accent(horizon).opacity(0.16) : .clear)
                .animation(.easeOut(duration: 0.15), value: targeted))
        .dropDestination(for: String.self) { ids, _ in
            targeted = false
            if let first = ids.first, let uid = UUID(uuidString: first) { onDrop(uid); return true }
            return false
        } isTargeted: { targeted = $0 }
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(Theme.accent(horizon)).frame(width: 9, height: 9)
                Text(horizon.label(loc.lang))
                    .font(Theme.display(18)).foregroundStyle(.white)
            }
            Text(horizon.phrase(loc.lang))
                .font(Theme.displayLight(11)).italic()
                .foregroundStyle(.white.opacity(0.5))
            HorizonRing(progress: laneProgress, color: Theme.accent(horizon),
                        lineWidth: 5, size: 40)
                .padding(.top, 2)
            Text("\(items.count) " + loc.t("jalon" + (items.count == 1 ? "" : "s"),
                                            "milestone" + (items.count == 1 ? "" : "s")))
                .font(Theme.body(10)).foregroundStyle(.white.opacity(0.45))
        }
        .frame(width: 110, alignment: .leading)
    }

    private var cards: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                if items.isEmpty {
                    emptyLane
                } else {
                    ForEach(items) { ms in
                        MilestoneCard(milestone: ms)
                            .opacity(draggingID == ms.id ? 0.45 : 1)
                            .draggable(ms.id.uuidString) {
                                MilestoneCard(milestone: ms).frame(width: 220)
                                    .onAppear { draggingID = ms.id }
                            }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var emptyLane: some View {
        Text(loc.t("Glissez un jalon ici", "Drag a milestone here"))
            .font(Theme.body(12)).italic()
            .foregroundStyle(.white.opacity(0.3))
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    .foregroundStyle(.white.opacity(0.12)))
    }
}

/// A draggable milestone card.
struct MilestoneCard: View {
    @EnvironmentObject var loc: LocManager
    @Bindable var milestone: Milestone
    @State private var showDetail = false

    var body: some View {
        Button { showDetail = true } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle().fill(Theme.statusColor(milestone.status)).frame(width: 7, height: 7)
                    Text(milestone.status.label(loc.lang).uppercased())
                        .font(Theme.mono(8.5)).tracking(0.5)
                        .foregroundStyle(Theme.statusColor(milestone.status))
                    Spacer()
                    HorizonRing(progress: milestone.progress,
                                color: Theme.accent(milestone.horizon),
                                lineWidth: 3.5, size: 26)
                }
                Text(milestone.title)
                    .font(Theme.body(14)).fontWeight(.medium)
                    .foregroundStyle(Theme.parchmentInk)
                    .lineLimit(3).multilineTextAlignment(.leading)
                if !milestone.definitionOfDone.isEmpty {
                    Label(milestone.definitionOfDone, systemImage: "checkmark.circle")
                        .font(Theme.body(10.5))
                        .foregroundStyle(Theme.parchmentInk.opacity(0.6))
                        .lineLimit(2)
                }
                if !milestone.allSteps.isEmpty {
                    let done = milestone.allSteps.filter(\.isDone).count
                    Text("\(done)/\(milestone.allSteps.count) " + loc.t("étapes", "steps"))
                        .font(Theme.mono(9.5)).foregroundStyle(Theme.parchmentInk.opacity(0.5))
                }
            }
            .padding(13)
            .frame(width: 224, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 13)
                    .fill(Theme.parchment)
                    .shadow(color: .black.opacity(0.28), radius: 7, y: 3))
            .overlay(
                RoundedRectangle(cornerRadius: 13)
                    .strokeBorder(Theme.accent(milestone.horizon).opacity(0.5), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            MilestoneEditor(milestone: milestone)
        }
    }
}
