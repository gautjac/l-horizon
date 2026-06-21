import SwiftUI
import SwiftData

@main
struct LHorizonApp: App {
    @StateObject private var loc = LocManager.shared

    /// The shared SwiftData container. On `-demoSeed 1` (or first empty launch)
    /// it seeds a friendly demo intention so the board is never blank.
    let container: ModelContainer

    init() {
        let schema = Schema([Intention.self, Milestone.self, Step.self, ReviewLog.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Fall back to an in-memory store so the app still launches if the
            // on-disk store is incompatible (e.g. schema change during dev).
            let mem = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            container = try! ModelContainer(for: schema, configurations: [mem])
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(loc)
                .frame(minWidth: 1040, minHeight: 680)
                .task { @MainActor in
                    // Seed on first run or when explicitly requested for demos.
                    let args = ProcessInfo.processInfo.arguments
                    if args.contains("-demoSeed") || args.contains("1") {
                        Seed.seedIfEmpty(container.mainContext)
                    } else {
                        Seed.seedIfEmpty(container.mainContext)
                    }
                }
        }
        .modelContainer(container)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1240, height: 800)
        .commands {
            CommandGroup(replacing: .help) {
                Button("L'Horizon — aide") {}
                    .disabled(true)
            }
        }
    }
}
