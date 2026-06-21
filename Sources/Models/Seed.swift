import Foundation
import SwiftData

/// Friendly demo / onboarding seed. Builds one richly-populated intention so the
/// board, rings, and review ritual all have something to show on first run and
/// in screenshots. Idempotent: only seeds when the store is empty.
enum Seed {

    @MainActor
    static func seedIfEmpty(_ context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<Intention>())) ?? 0
        guard count == 0 else { return }
        insertDemo(context)
        try? context.save()
    }

    @MainActor
    @discardableResult
    static func insertDemo(_ context: ModelContext) -> Intention {
        let cal = Calendar.horizon
        let anchor = cal.date(byAdding: .month, value: -1, to: Date()) ?? Date()

        let intention = Intention(
            title: t("Réaliser le portrait de Patrick Norman",
                     "Direct the Patrick Norman portrait film"),
            detail: t("Un long métrage documentaire, structuré guitare par guitare. De l'écriture au montage final.",
                      "A feature documentary, structured guitar by guitar. From writing to final cut."),
            anchorDate: anchor, topHorizon: .fiveYears)
        context.insert(intention)

        func m(_ title: String, _ h: Horizon, dod: String, status: MilestoneStatus,
               steps: [(String, Bool)], target: Date? = nil, idx: Int) -> Milestone {
            let ms = Milestone(title: title, horizon: h, definitionOfDone: dod,
                               status: status, targetDate: target, sortIndex: idx)
            ms.intention = intention
            context.insert(ms)
            for (i, s) in steps.enumerated() {
                let step = Step(text: s.0, isDone: s.1, sortIndex: i)
                step.milestone = ms
                context.insert(step)
            }
            return ms
        }

        func date(_ months: Int) -> Date { cal.date(byAdding: .month, value: months, to: anchor) ?? anchor }

        // 3 mois — concrete next steps.
        _ = m(t("Boucler le traitement d'écriture", "Lock the treatment"),
              .threeMonths,
              dod: t("Document de 12 pages validé par le producteur.", "12-page document signed off by the producer."),
              status: .active,
              steps: [(t("Relire les entrevues de repérage", "Re-read the scouting interviews"), true),
                      (t("Structurer les six guitares", "Structure the six guitars"), true),
                      (t("Écrire l'arc émotionnel", "Write the emotional arc"), false)],
              target: date(2), idx: 0)
        _ = m(t("Confirmer le premier tournage", "Confirm the first shoot"),
              .threeMonths,
              dod: t("Dates et lieu réservés avec Patrick.", "Dates and location booked with Patrick."),
              status: .planned,
              steps: [(t("Appeler son gérant", "Call his manager"), false),
                      (t("Réserver la salle", "Book the room"), false)],
              target: date(3), idx: 1)

        // 6 mois.
        _ = m(t("Financer le développement", "Fund development"),
              .sixMonths,
              dod: t("Demande SODEC déposée.", "SODEC application filed."),
              status: .planned,
              steps: [(t("Monter le budget", "Build the budget"), false),
                      (t("Lettre d'intention du diffuseur", "Broadcaster letter of intent"), false)],
              target: date(5), idx: 0)

        // 1 an.
        _ = m(t("Terminer le tournage principal", "Wrap principal photography"),
              .oneYear,
              dod: t("Les six guitares filmées.", "All six guitars filmed."),
              status: .planned,
              steps: [(t("Calendrier de tournage", "Shooting schedule"), false)],
              target: date(11), idx: 0)
        // One that has slipped, to exercise the re-flow ritual.
        _ = m(t("Premier montage assemblé", "First assembly cut"),
              .oneYear,
              dod: t("Bout-à-bout de 90 minutes.", "90-minute string-out."),
              status: .slipped,
              steps: [(t("Dérushage", "Logging the rushes"), false)],
              target: date(-1), idx: 1)

        // 3 ans.
        _ = m(t("Sortie en festival", "Festival premiere"),
              .threeYears,
              dod: t("Sélectionné dans un festival majeur.", "Selected by a major festival."),
              status: .planned,
              steps: [(t("Stratégie festival", "Festival strategy"), false)], idx: 0)

        // 5 ans — the summit.
        _ = m(t("Distribution et héritage", "Distribution and legacy"),
              .fiveYears,
              dod: t("Le film vit : diffusé, archivé, transmis.", "The film lives: aired, archived, passed on."),
              status: .planned,
              steps: [(t("Plan de diffusion long terme", "Long-term distribution plan"), false)], idx: 0)

        // A past review entry for the log.
        let review = ReviewLog(
            date: cal.date(byAdding: .weekOfYear, value: -1, to: Date()) ?? Date(),
            cadence: .weekly,
            summary: t("Bonne lancée sur le traitement. Le montage a glissé — on lui redonne de l'air.",
                       "Good momentum on the treatment. The assembly slipped — give it room."),
            advancedCount: 2, slippedCount: 1,
            reflowNote: t("Reporter le premier montage de quelques mois.",
                          "Push the first assembly out a few months."))
        review.intention = intention
        context.insert(review)

        return intention
    }
}
