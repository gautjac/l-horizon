import Foundation
import SwiftData

/// One milestone in a starter template — bilingual, with a target horizon, a
/// definition of done, and its action steps.
struct MilestoneTemplate {
    let titleFR: String, titleEN: String
    let horizon: Horizon
    let dodFR: String, dodEN: String
    let stepsFR: [String], stepsEN: [String]
}

/// A starter cascade for a common long-horizon intention. Selecting one seeds a
/// full board instead of a blank slate; the user renames and reshapes from there.
struct IntentionTemplate: Identifiable {
    let id: String
    let titleFR: String, titleEN: String
    let detailFR: String, detailEN: String
    let topHorizon: Horizon
    let milestones: [MilestoneTemplate]

    func title(_ l: Lang) -> String { l == .fr ? titleFR : titleEN }
    func detail(_ l: Lang) -> String { l == .fr ? detailFR : detailEN }
    var milestoneCount: Int { milestones.count }
}

/// The template catalogue + instantiation into SwiftData. The catalogue is pure
/// data (unit-tested for well-formedness); `instantiate` builds real models.
enum Templates {

    static let all: [IntentionTemplate] = [documentary, book, album]

    static func byID(_ id: String) -> IntentionTemplate? { all.first { $0.id == id } }

    /// Build a real `Intention` (with milestones + steps) from a template, in the
    /// active language. Optional overrides let the New-Intention sheet pre-fill.
    @MainActor
    @discardableResult
    static func instantiate(_ t: IntentionTemplate, into context: ModelContext,
                            title: String? = nil, detail: String? = nil,
                            lang: Lang = LocManager.shared.lang, sortIndex: Int = 0) -> Intention {
        let intention = Intention(title: title ?? t.title(lang),
                                  detail: detail ?? t.detail(lang),
                                  topHorizon: t.topHorizon, sortIndex: sortIndex)
        context.insert(intention)
        for (i, mt) in t.milestones.enumerated() {
            let m = Milestone(title: lang == .fr ? mt.titleFR : mt.titleEN,
                              horizon: mt.horizon,
                              definitionOfDone: lang == .fr ? mt.dodFR : mt.dodEN,
                              sortIndex: i)
            m.intention = intention
            context.insert(m)
            let steps = lang == .fr ? mt.stepsFR : mt.stepsEN
            for (j, s) in steps.enumerated() {
                let step = Step(text: s, sortIndex: j)
                step.milestone = m
                context.insert(step)
            }
        }
        return intention
    }

    // MARK: Catalogue

    static let documentary = IntentionTemplate(
        id: "documentary",
        titleFR: "Réaliser un long métrage documentaire",
        titleEN: "Direct a feature documentary",
        detailFR: "De l'écriture au montage final, un film porté de bout en bout.",
        detailEN: "From writing to final cut — a film carried end to end.",
        topHorizon: .fiveYears,
        milestones: [
            MilestoneTemplate(
                titleFR: "Boucler le traitement d'écriture", titleEN: "Lock the treatment",
                horizon: .threeMonths,
                dodFR: "Document validé par un premier lecteur.", dodEN: "Signed off by a first reader.",
                stepsFR: ["Écrire la note d'intention", "Structurer l'arc", "Faire relire"],
                stepsEN: ["Write the intention note", "Structure the arc", "Get it read"]),
            MilestoneTemplate(
                titleFR: "Financer le développement", titleEN: "Fund development",
                horizon: .sixMonths,
                dodFR: "Une demande de financement déposée.", dodEN: "A funding application filed.",
                stepsFR: ["Monter le budget", "Trouver un diffuseur"],
                stepsEN: ["Build the budget", "Find a broadcaster"]),
            MilestoneTemplate(
                titleFR: "Terminer le tournage principal", titleEN: "Wrap principal photography",
                horizon: .oneYear,
                dodFR: "Toute la matière tournée.", dodEN: "All the footage shot.",
                stepsFR: ["Calendrier de tournage", "Repérages"],
                stepsEN: ["Shooting schedule", "Location scouting"]),
            MilestoneTemplate(
                titleFR: "Verrouiller le montage", titleEN: "Lock the edit",
                horizon: .threeYears,
                dodFR: "Montage image approuvé.", dodEN: "Picture lock approved.",
                stepsFR: ["Bout-à-bout", "Mixage et étalonnage"],
                stepsEN: ["String-out", "Mix and grade"]),
            MilestoneTemplate(
                titleFR: "Sortie et diffusion", titleEN: "Release and distribution",
                horizon: .fiveYears,
                dodFR: "Le film est vu : festival, salle ou diffusion.", dodEN: "The film is seen: festival, cinema, or broadcast.",
                stepsFR: ["Stratégie festival", "Plan de diffusion"],
                stepsEN: ["Festival strategy", "Distribution plan"]),
        ])

    static let book = IntentionTemplate(
        id: "book",
        titleFR: "Écrire et publier un livre",
        titleEN: "Write and publish a book",
        detailFR: "De la première page au livre entre les mains d'un lecteur.",
        detailEN: "From the first page to a book in a reader's hands.",
        topHorizon: .threeYears,
        milestones: [
            MilestoneTemplate(
                titleFR: "Établir la routine d'écriture", titleEN: "Establish the writing routine",
                horizon: .threeMonths,
                dodFR: "Quatre semaines d'écriture tenues.", dodEN: "Four weeks of writing held.",
                stepsFR: ["Fixer un créneau quotidien", "Écrire le premier chapitre"],
                stepsEN: ["Set a daily slot", "Write chapter one"]),
            MilestoneTemplate(
                titleFR: "Terminer le premier jet", titleEN: "Finish the first draft",
                horizon: .oneYear,
                dodFR: "Manuscrit complet de bout en bout.", dodEN: "A complete end-to-end manuscript.",
                stepsFR: ["Plan détaillé", "Écrire le milieu", "Écrire la fin"],
                stepsEN: ["Detailed outline", "Write the middle", "Write the end"]),
            MilestoneTemplate(
                titleFR: "Réviser avec un regard extérieur", titleEN: "Revise with outside eyes",
                horizon: .oneYear,
                dodFR: "Deux passes de révision et des retours reçus.", dodEN: "Two revision passes and feedback in hand.",
                stepsFR: ["Auto-révision", "Lecteurs bêta"],
                stepsEN: ["Self-revision", "Beta readers"]),
            MilestoneTemplate(
                titleFR: "Publier", titleEN: "Publish",
                horizon: .threeYears,
                dodFR: "Le livre est disponible à l'achat.", dodEN: "The book is available to buy.",
                stepsFR: ["Choisir la voie (édition/auto)", "Maquette et couverture"],
                stepsEN: ["Choose the path (press/self)", "Layout and cover"]),
        ])

    static let album = IntentionTemplate(
        id: "album",
        titleFR: "Enregistrer et lancer un album",
        titleEN: "Record and release an album",
        detailFR: "Des maquettes à la sortie, une œuvre menée à terme.",
        detailEN: "From demos to release — a body of work carried through.",
        topHorizon: .threeYears,
        milestones: [
            MilestoneTemplate(
                titleFR: "Réunir les maquettes", titleEN: "Gather the demos",
                horizon: .threeMonths,
                dodFR: "Huit maquettes enregistrées.", dodEN: "Eight demos recorded.",
                stepsFR: ["Écrire trois nouvelles idées", "Enregistrer des maquettes brutes"],
                stepsEN: ["Write three new ideas", "Track rough demos"]),
            MilestoneTemplate(
                titleFR: "Arranger et pré-produire", titleEN: "Arrange and pre-produce",
                horizon: .sixMonths,
                dodFR: "Arrangements arrêtés pour l'album.", dodEN: "Arrangements settled for the record.",
                stepsFR: ["Choisir les titres", "Répétitions"],
                stepsEN: ["Choose the tracks", "Rehearsals"]),
            MilestoneTemplate(
                titleFR: "Enregistrer et mixer", titleEN: "Record and mix",
                horizon: .oneYear,
                dodFR: "Masters approuvés.", dodEN: "Masters approved.",
                stepsFR: ["Sessions studio", "Mixage et mastering"],
                stepsEN: ["Studio sessions", "Mix and master"]),
            MilestoneTemplate(
                titleFR: "Lancer l'album", titleEN: "Release the album",
                horizon: .threeYears,
                dodFR: "L'album est sorti et écouté.", dodEN: "The album is out and being heard.",
                stepsFR: ["Plan de sortie", "Concert de lancement"],
                stepsEN: ["Release plan", "Launch show"]),
        ])
}
