import SwiftUI
import SwiftData

/// Create or edit a milestone. When `milestone` is nil it creates a new one in
/// `intention` at `horizon`.
struct MilestoneEditor: View {
    @EnvironmentObject var loc: LocManager
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var milestone: Milestone?
    var intention: Intention?
    var horizon: Horizon = .threeMonths
    /// When creating from the calendar, pre-fill (and enable) the target date.
    var presetDate: Date?

    @State private var title = ""
    @State private var dod = ""
    @State private var notes = ""
    @State private var horizonSel: Horizon = .threeMonths
    @State private var statusSel: MilestoneStatus = .planned
    @State private var hasTarget = false
    @State private var target = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(milestone == nil ? loc.t("Nouveau jalon", "New milestone")
                                   : loc.t("Modifier le jalon", "Edit milestone"))
                .font(Theme.display(20))
                .padding(.bottom, 12)

            Form {
                TextField(loc.t("Titre", "Title"), text: $title)
                Picker(loc.t("Horizon", "Horizon"), selection: $horizonSel) {
                    ForEach(Horizon.cascade) { h in Text(h.label(loc.lang)).tag(h) }
                }
                Picker(loc.t("Statut", "Status"), selection: $statusSel) {
                    ForEach(MilestoneStatus.allCases) { s in Text(s.label(loc.lang)).tag(s) }
                }
                TextField(loc.t("Fait quand… (définition)", "Done when… (definition)"), text: $dod, axis: .vertical)
                    .lineLimit(2...4)
                TextField(loc.t("Notes", "Notes"), text: $notes, axis: .vertical)
                    .lineLimit(2...5)
                Toggle(loc.t("Date cible", "Target date"), isOn: $hasTarget)
                if hasTarget {
                    DatePicker(loc.t("Cible", "Target"), selection: $target, displayedComponents: .date)
                }
            }
            .formStyle(.grouped)
            .frame(height: 360)

            HStack {
                if milestone != nil {
                    Button(role: .destructive) { remove() } label: {
                        Label(loc.t("Supprimer", "Delete"), systemImage: "trash")
                    }
                }
                Spacer()
                Button(loc.t("Annuler", "Cancel")) { dismiss() }
                Button(loc.t("Enregistrer", "Save")) { save() }
                    .buttonStyle(.borderedProminent).tint(Theme.dawn)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 10)
        }
        .padding(22)
        .frame(width: 480)
        .onAppear(perform: load)
    }

    private func load() {
        if let m = milestone {
            title = m.title; dod = m.definitionOfDone; notes = m.notes
            horizonSel = m.horizon; statusSel = m.status
            if let tgt = m.targetDate { hasTarget = true; target = tgt }
        } else {
            horizonSel = horizon
            if let preset = presetDate { hasTarget = true; target = preset }
        }
    }

    private func save() {
        let m: Milestone
        if let existing = milestone {
            m = existing
        } else {
            m = Milestone(title: "", horizon: horizonSel)
            m.intention = intention
            m.sortIndex = ((intention?.milestones(at: horizonSel).map(\.sortIndex).max()) ?? -1) + 1
            context.insert(m)
        }
        m.title = title.trimmingCharacters(in: .whitespaces)
        m.definitionOfDone = dod
        m.notes = notes
        m.horizon = horizonSel
        m.status = statusSel
        m.targetDate = hasTarget ? target : nil
        try? context.save()
        if let owner = m.intention, owner.calendarSyncEnabled {
            Task { try? await CalendarSync.shared.sync(intention: owner, context: context, lang: loc.lang) }
        }
        dismiss()
    }

    private func remove() {
        if let m = milestone {
            let owner = m.intention
            let eventID = m.calendarEventID
            context.delete(m)
            try? context.save()
            if let owner, owner.calendarSyncEnabled {
                Task { await CalendarSync.shared.removeEvent(id: eventID) }
            }
        }
        dismiss()
    }
}

/// Edit an existing intention's title / detail / anchor / summit horizon, plus
/// its review cadence and Calendar sync.
struct IntentionEditor: View {
    @EnvironmentObject var loc: LocManager
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var intention: Intention

    @State private var syncMessage: String?
    @State private var syncing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(loc.t("Modifier l'intention", "Edit intention"))
                .font(Theme.display(20)).padding(.bottom, 12)
            Form {
                Section {
                    TextField(loc.t("Titre", "Title"), text: $intention.title)
                    TextField(loc.t("Le pourquoi / contexte", "The why / context"),
                              text: $intention.detail, axis: .vertical).lineLimit(2...5)
                    DatePicker(loc.t("Ancrage", "Anchor"), selection: $intention.anchorDate,
                               displayedComponents: .date)
                    Picker(loc.t("Horizon sommet", "Summit horizon"), selection: Binding(
                        get: { intention.topHorizon }, set: { intention.topHorizon = $0 })) {
                        ForEach(Horizon.cascade) { h in Text(h.label(loc.lang)).tag(h) }
                    }
                }
                Section(loc.t("Rythme de revue", "Review rhythm")) {
                    Picker(loc.t("Cadence", "Cadence"), selection: Binding(
                        get: { intention.reviewCadence }, set: { intention.reviewCadence = $0 })) {
                        ForEach(ReviewCadence.allCases) { c in Text(c.label(loc.lang)).tag(c) }
                    }
                }
                Section(loc.t("Calendrier système", "System Calendar")) {
                    Toggle(loc.t("Synchroniser les dates cibles", "Sync target dates"),
                           isOn: $intention.calendarSyncEnabled)
                    if intention.calendarSyncEnabled {
                        Button {
                            Task { await runSync() }
                        } label: {
                            Label(syncing ? loc.t("Synchronisation…", "Syncing…")
                                          : loc.t("Synchroniser maintenant", "Sync now"),
                                  systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(syncing)
                    }
                    if let syncMessage {
                        Text(syncMessage).font(Theme.body(11)).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped).frame(height: 420)
            HStack {
                Spacer()
                Button(loc.t("Terminé", "Done")) { finish() }
                    .buttonStyle(.borderedProminent).tint(Theme.dawn)
            }
            .padding(.top, 10)
        }
        .padding(22).frame(width: 480)
        .onChange(of: intention.calendarSyncEnabled) { _, enabled in
            Task {
                if enabled { await runSync() }
                else { await CalendarSync.shared.removeAll(for: intention, context: context)
                       syncMessage = loc.t("Événements retirés.", "Events removed.") }
            }
        }
    }

    private func runSync() async {
        syncing = true; syncMessage = nil
        do {
            let n = try await CalendarSync.shared.sync(intention: intention, context: context, lang: loc.lang)
            syncMessage = loc.t("\(n) jalon(s) synchronisé(s).", "\(n) milestone(s) synced.")
        } catch {
            syncMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        syncing = false
    }

    private func finish() {
        try? context.save()
        let all = (try? context.fetch(FetchDescriptor<Intention>())) ?? []
        Task { await NotificationManager.shared.rescheduleReviewReminders(all, lang: loc.lang) }
        dismiss()
    }
}

/// Create a brand-new intention, optionally launching straight into AI breakdown.
struct NewIntentionView: View {
    @EnvironmentObject var loc: LocManager
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var existing: [Intention]
    var onCreate: (UUID) -> Void

    @State private var title = ""
    @State private var detail = ""
    @State private var topHorizon: Horizon = .fiveYears
    @State private var templateID: String?      // nil = blank

    private var template: IntentionTemplate? { templateID.flatMap(Templates.byID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(loc.t("Nouvelle intention", "New intention"))
                    .font(Theme.display(22))
                Text(loc.t("Visez loin. On déroulera le chemin.", "Aim far. We'll lay out the path."))
                    .font(Theme.displayLight(13)).italic().foregroundStyle(.secondary)
            }
            .padding(.bottom, 14)
            Form {
                Picker(loc.t("Modèle", "Template"), selection: $templateID) {
                    Text(loc.t("Vierge", "Blank")).tag(String?.none)
                    ForEach(Templates.all) { t in Text(t.title(loc.lang)).tag(String?.some(t.id)) }
                }
                TextField(loc.t("Intention (ex. réaliser un film)", "Intention (e.g. direct a film)"),
                          text: $title, axis: .vertical).lineLimit(1...3)
                TextField(loc.t("Le pourquoi / contexte (optionnel)", "The why / context (optional)"),
                          text: $detail, axis: .vertical).lineLimit(2...5)
                if let template {
                    LabeledContent(loc.t("Horizon sommet", "Summit horizon"),
                                   value: template.topHorizon.label(loc.lang))
                    Label(loc.t("Inclut \(template.milestoneCount) jalons de départ",
                                "Includes \(template.milestoneCount) starter milestones"),
                          systemImage: "square.stack.3d.up")
                        .font(Theme.body(11)).foregroundStyle(.secondary)
                } else {
                    Picker(loc.t("Horizon sommet", "Summit horizon"), selection: $topHorizon) {
                        ForEach(Horizon.cascade) { h in Text(h.label(loc.lang)).tag(h) }
                    }
                }
            }
            .formStyle(.grouped).frame(height: 320)
            HStack {
                Spacer()
                Button(loc.t("Annuler", "Cancel")) { dismiss() }
                Button(loc.t("Créer", "Create")) { create() }
                    .buttonStyle(.borderedProminent).tint(Theme.dawn)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 10)
        }
        .padding(24).frame(width: 500)
        .onChange(of: templateID) { _, _ in applyTemplate() }
    }

    /// Pre-fill the fields from the chosen template (blank leaves them as typed).
    private func applyTemplate() {
        guard let template else { return }
        title = template.title(loc.lang)
        detail = template.detail(loc.lang)
        topHorizon = template.topHorizon
    }

    private func create() {
        let sortIndex = (existing.map(\.sortIndex).max() ?? -1) + 1
        let cleanTitle = title.trimmingCharacters(in: .whitespaces)
        let intention: Intention
        if let template {
            intention = Templates.instantiate(template, into: context,
                                              title: cleanTitle, detail: detail,
                                              lang: loc.lang, sortIndex: sortIndex)
        } else {
            intention = Intention(title: cleanTitle, detail: detail,
                                  topHorizon: topHorizon, sortIndex: sortIndex)
            context.insert(intention)
        }
        try? context.save()
        onCreate(intention.id)
        dismiss()
    }
}
