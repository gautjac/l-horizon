import SwiftUI

/// First-run empty state — calm horizon lines and a gentle invitation, plus a
/// one-tap demo seed so the board is never daunting.
struct EmptyStateView: View {
    @EnvironmentObject var loc: LocManager
    @Environment(\.modelContext) private var context
    var onCreate: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                HorizonLines(count: 5, color: Theme.dawn)
                    .frame(width: 320, height: 130).opacity(0.8)
                Image(systemName: "sun.haze.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(Theme.glow)
                    .offset(y: -8)
            }
            VStack(spacing: 6) {
                Text("L'Horizon").font(Theme.display(38)).foregroundStyle(.white)
                Text(loc.t("Cinq horizons. Une intention à la fois.",
                           "Five horizons. One intention at a time."))
                    .font(Theme.displayLight(16)).italic().foregroundStyle(.white.opacity(0.7))
            }
            VStack(alignment: .leading, spacing: 10) {
                onboardLine("3", loc.t("3 mois — le prochain pas concret.", "3 months — the next concrete step."))
                onboardLine("6", loc.t("6 mois — ce qui prend forme.", "6 months — what's taking shape."))
                onboardLine("1", loc.t("1 an — le jalon de l'année.", "1 year — this year's milestone."))
                onboardLine("3", loc.t("3 ans — la trajectoire.", "3 years — the trajectory."))
                onboardLine("5", loc.t("5 ans — le sommet visé.", "5 years — the summit you aim for."))
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.05)))

            HStack(spacing: 12) {
                Button { onCreate() } label: {
                    Label(loc.t("Nouvelle intention", "New intention"), systemImage: "plus")
                        .font(Theme.body(14)).padding(.horizontal, 6).padding(.vertical, 3)
                }
                .buttonStyle(.borderedProminent).tint(Theme.dawn)
                Button { Seed.insertDemo(context); try? context.save() } label: {
                    Label(loc.t("Voir un exemple", "See an example"), systemImage: "sparkle.magnifyingglass")
                        .font(Theme.body(14))
                }
                .buttonStyle(.bordered).tint(.white)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func onboardLine(_ n: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Text(n).font(Theme.mono(13)).foregroundStyle(Theme.nightDeep)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Theme.dawnSoft))
            Text(text).font(Theme.body(13.5)).foregroundStyle(.white.opacity(0.85))
            Spacer()
        }
    }
}
