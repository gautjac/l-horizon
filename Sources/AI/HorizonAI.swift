import Foundation

/// A milestone proposed by the AI breakdown, decoded from the forced-tool JSON.
struct ProposedMilestone: Identifiable {
    let id = UUID()
    var title: String
    var horizon: Horizon
    var definitionOfDone: String
    var steps: [String]
}

/// A re-flow suggestion for one milestone, decoded from the forced-tool JSON.
struct ReflowSuggestion: Identifiable {
    let id = UUID()
    var milestoneTitle: String
    var suggestedHorizon: Horizon?
    var note: String
}

/// High-level AI operations for L'Horizon — the milestone breakdown and the
/// review re-flow. Wraps `OpusClient` with the two tool schemas and parsing.
enum HorizonAI {

    private static func horizonKey(_ h: Horizon) -> String {
        switch h {
        case .threeMonths: return "3mo"
        case .sixMonths:   return "6mo"
        case .oneYear:     return "1yr"
        case .threeYears:  return "3yr"
        case .fiveYears:   return "5yr"
        }
    }

    private static func horizon(fromKey k: String) -> Horizon? {
        switch k.lowercased() {
        case "3mo", "3months", "threemonths": return .threeMonths
        case "6mo", "6months", "sixmonths":   return .sixMonths
        case "1yr", "1year", "oneyear":       return .oneYear
        case "3yr", "3years", "threeyears":   return .threeYears
        case "5yr", "5years", "fiveyears":    return .fiveYears
        default: return nil
        }
    }

    // MARK: Milestone breakdown.

    /// Ask the model to break an intention into a milestone cascade. `lang`
    /// drives the language of the generated content (FR-first).
    static func breakdown(intention: String, context: String, topHorizon: Horizon,
                          lang: Lang) async throws -> [ProposedMilestone] {
        let system = lang == .fr
            ? """
              Tu es un planificateur de vie qui décompose une intention à long terme en jalons \
              répartis sur cinq horizons emboîtés : 3 mois, 6 mois, 1 an, 3 ans, 5 ans. \
              Chaque jalon vise un horizon précis, possède une définition de « fait » concrète et \
              vérifiable, et 2 à 5 étapes d'action. Place plus de jalons rapprochés (3-6 mois) que \
              lointains. L'horizon le plus proche doit toujours contenir au moins un premier pas \
              concret. Rédige en français québécois, clair et chaleureux.
              """
            : """
              You are a life planner who breaks a long-term intention into milestones spread across \
              five nested horizons: 3 months, 6 months, 1 year, 3 years, 5 years. Each milestone \
              targets one horizon, has a concrete, checkable definition of done, and 2–5 action \
              steps. Place more near-term milestones (3–6 months) than far ones. The nearest \
              horizon must always hold at least one concrete first step. Write warm, clear prose.
              """

        let user = lang == .fr
            ? "Intention (horizon visé : \(topHorizon.label(.fr))) :\n\(intention)\n\nContexte :\n\(context.isEmpty ? "(aucun)" : context)"
            : "Intention (target horizon: \(topHorizon.label(.en))):\n\(intention)\n\nContext:\n\(context.isEmpty ? "(none)" : context)"

        let tool = OpusClient.Tool(
            name: "propose_milestones",
            description: "Return the milestone cascade for the intention.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "milestones": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "properties": [
                                "title": ["type": "string"],
                                "horizon": ["type": "string",
                                            "enum": ["3mo", "6mo", "1yr", "3yr", "5yr"]],
                                "definition_of_done": ["type": "string"],
                                "steps": ["type": "array", "items": ["type": "string"]],
                            ],
                            "required": ["title", "horizon", "definition_of_done", "steps"],
                        ],
                    ]
                ],
                "required": ["milestones"],
            ])

        let result = try await OpusClient.runTool(system: system, userText: user, tool: tool)
        guard let arr = result["milestones"] as? [[String: Any]] else { return [] }
        return arr.compactMap { m in
            guard let title = m["title"] as? String,
                  let hk = m["horizon"] as? String,
                  let h = horizon(fromKey: hk) else { return nil }
            let dod = m["definition_of_done"] as? String ?? ""
            let steps = (m["steps"] as? [String]) ?? []
            return ProposedMilestone(title: title, horizon: h, definitionOfDone: dod, steps: steps)
        }
    }

    // MARK: Review re-flow.

    /// Ask the model to re-flow upcoming/slipped milestones forward and write a
    /// short review summary. `snapshot` is a plain text description built by the
    /// caller from the current plan + the deterministic `Reflow` result.
    static func reflow(intentionTitle: String, snapshot: String,
                       lang: Lang) async throws -> (summary: String, suggestions: [ReflowSuggestion]) {
        let system = lang == .fr
            ? """
              Tu animes une revue de planification. On te donne l'état courant d'une intention et \
              de ses jalons (avec progrès et statut), plus une proposition automatique de \
              réorganisation. Replanifie ce qui a glissé ou ce qui s'en vient : pour chaque jalon \
              à ajuster, propose éventuellement un nouvel horizon (3mo/6mo/1yr/3yr/5yr) et une note \
              brève et actionnable. Termine par un résumé chaleureux de 2-3 phrases. En français.
              """
            : """
              You run a planning review. You are given the current state of an intention and its \
              milestones (progress + status) plus an automatic re-organization proposal. Re-plan \
              what slipped or is coming up: for each milestone to adjust, optionally propose a new \
              horizon (3mo/6mo/1yr/3yr/5yr) and a brief, actionable note. End with a warm 2–3 \
              sentence summary.
              """

        let tool = OpusClient.Tool(
            name: "reflow_plan",
            description: "Return re-flow adjustments and a review summary.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "summary": ["type": "string"],
                    "adjustments": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "properties": [
                                "milestone": ["type": "string"],
                                "new_horizon": ["type": "string",
                                                "enum": ["3mo", "6mo", "1yr", "3yr", "5yr", "keep"]],
                                "note": ["type": "string"],
                            ],
                            "required": ["milestone", "note"],
                        ],
                    ],
                ],
                "required": ["summary", "adjustments"],
            ])

        let user = "Intention : \(intentionTitle)\n\n\(snapshot)"
        let result = try await OpusClient.runTool(system: system, userText: user, tool: tool)
        let summary = result["summary"] as? String ?? ""
        let arr = result["adjustments"] as? [[String: Any]] ?? []
        let suggestions: [ReflowSuggestion] = arr.compactMap { a in
            guard let title = a["milestone"] as? String else { return nil }
            let note = a["note"] as? String ?? ""
            let h = (a["new_horizon"] as? String).flatMap { $0 == "keep" ? nil : horizon(fromKey: $0) }
            return ReflowSuggestion(milestoneTitle: title, suggestedHorizon: h, note: note)
        }
        return (summary, suggestions)
    }

    // MARK: Weekly check-in.

    /// A reflective weekly check-in: a warm 2–3 sentence read on progress and
    /// risk, plus a few concrete focus actions for the coming week. Distinct from
    /// the re-flow (which reshuffles horizons); this is narrative + next steps.
    static func checkIn(intentionTitle: String, snapshot: String,
                        lang: Lang) async throws -> (summary: String, focus: [String]) {
        let system = lang == .fr
            ? """
              Tu fais le bilan hebdomadaire d'une intention à long terme. On te donne l'état \
              courant des jalons (statut et progrès). Écris un court bilan chaleureux de 2 à 3 \
              phrases : ce qui a avancé, ce qui est à risque. Puis propose de 2 à 4 actions \
              concrètes et réalistes pour la semaine qui vient. En français québécois.
              """
            : """
              You run a weekly check-in on a long-term intention. You are given the current state \
              of its milestones (status and progress). Write a warm 2–3 sentence read: what moved, \
              what's at risk. Then propose 2–4 concrete, realistic focus actions for the coming \
              week. Warm, clear prose.
              """

        let tool = OpusClient.Tool(
            name: "weekly_checkin",
            description: "Return a short check-in summary and this week's focus actions.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "summary": ["type": "string"],
                    "focus": ["type": "array", "items": ["type": "string"]],
                ],
                "required": ["summary", "focus"],
            ])

        let user = "Intention : \(intentionTitle)\n\n\(snapshot)"
        let result = try await OpusClient.runTool(system: system, userText: user, tool: tool)
        let summary = result["summary"] as? String ?? ""
        let focus = (result["focus"] as? [String]) ?? []
        return (summary, focus)
    }
}
