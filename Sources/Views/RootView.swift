import SwiftUI
import SwiftData

/// Which workspace tab is showing for the selected intention.
enum Workspace: String, CaseIterable, Identifiable {
    case board, detail, review
    var id: String { rawValue }
    func label(_ lang: Lang) -> String {
        switch self {
        case .board:  return lang == .fr ? "Horizons" : "Horizons"
        case .detail: return lang == .fr ? "Détail"   : "Detail"
        case .review: return lang == .fr ? "Revue"    : "Review"
        }
    }
    var icon: String {
        switch self {
        case .board:  return "chart.bar.doc.horizontal"
        case .detail: return "list.bullet.indent"
        case .review: return "checkmark.seal"
        }
    }
}

/// The shell: a sidebar of intentions on the left, the chosen workspace on the
/// right, with the dawn-to-night sky as the through-line.
struct RootView: View {
    @EnvironmentObject var loc: LocManager
    @Environment(\.modelContext) private var context
    @Query(sort: \Intention.sortIndex) private var intentions: [Intention]

    @State private var selectedID: UUID?
    @State private var workspace: Workspace = .board
    @State private var showingNew = false

    private var selected: Intention? {
        intentions.first { $0.id == selectedID } ?? intentions.first
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 270, max: 320)
        } detail: {
            Group {
                if let intention = selected {
                    workspaceView(intention)
                } else {
                    EmptyStateView(onCreate: { showingNew = true })
                }
            }
            .background(Theme.sky.ignoresSafeArea())
        }
        .toolbar { toolbarContent }
        .sheet(isPresented: $showingNew) {
            NewIntentionView { newID in selectedID = newID; workspace = .board }
        }
        .onAppear { if selectedID == nil { selectedID = intentions.first?.id } }
        .tint(Theme.dawn)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $selectedID) {
            Section {
                ForEach(intentions) { intention in
                    IntentionRow(intention: intention)
                        .tag(intention.id)
                }
                .onDelete(perform: deleteIntentions)
            } header: {
                HStack {
                    Image(systemName: "mountain.2")
                    Text(loc.t("Intentions", "Intentions"))
                }
                .font(Theme.body(11))
            }
        }
        .safeAreaInset(edge: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("L'Horizon")
                    .font(Theme.display(26))
                Text(loc.t("cartographe du temps", "cartographer of time"))
                    .font(Theme.displayLight(12))
                    .italic()
                    .foregroundStyle(.secondary)
                HorizonLines(count: 5, color: Theme.dawn)
                    .frame(height: 26)
                    .opacity(0.7)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 6)
        }
    }

    @ViewBuilder
    private func workspaceView(_ intention: Intention) -> some View {
        VStack(spacing: 0) {
            WorkspacePicker(workspace: $workspace)
                .padding(.horizontal, 22)
                .padding(.top, 14)
                .padding(.bottom, 4)
            switch workspace {
            case .board:  HorizonBoardView(intention: intention)
            case .detail: GoalDetailView(intention: intention)
            case .review: ReviewView(intention: intention)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { showingNew = true } label: {
                Label(loc.t("Nouvelle intention", "New intention"), systemImage: "plus")
            }
        }
        ToolbarItem(placement: .automatic) {
            Button { loc.toggle() } label: {
                Text(loc.lang.label).font(Theme.mono(12)).frame(width: 26)
            }
            .help(loc.t("Changer de langue", "Toggle language"))
        }
    }

    private func deleteIntentions(_ offsets: IndexSet) {
        for i in offsets { context.delete(intentions[i]) }
        try? context.save()
    }
}

/// A single intention in the sidebar with its summit horizon + progress.
struct IntentionRow: View {
    @EnvironmentObject var loc: LocManager
    @Bindable var intention: Intention

    var body: some View {
        HStack(spacing: 10) {
            HorizonRing(progress: intention.progress,
                        color: Theme.accent(intention.topHorizon), size: 34, )
            VStack(alignment: .leading, spacing: 2) {
                Text(intention.title.isEmpty ? loc.t("Sans titre", "Untitled") : intention.title)
                    .font(Theme.body(13.5)).lineLimit(2)
                Text(loc.t("vers ", "toward ") + intention.topHorizon.label(loc.lang))
                    .font(Theme.body(10.5)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }
}

extension HorizonRing {
    init(progress: Double, color: Color, size: CGFloat) {
        self.init(progress: progress, color: color, lineWidth: 5, size: size)
    }
}

/// Segmented workspace switcher styled to the theme.
struct WorkspacePicker: View {
    @EnvironmentObject var loc: LocManager
    @Binding var workspace: Workspace

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Workspace.allCases) { w in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { workspace = w }
                } label: {
                    Label(w.label(loc.lang), systemImage: w.icon)
                        .font(Theme.body(13))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 9)
                                .fill(workspace == w ? Theme.dawn.opacity(0.92) : Color.white.opacity(0.06)))
                        .foregroundStyle(workspace == w ? Theme.nightDeep : .white.opacity(0.85))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }
}
