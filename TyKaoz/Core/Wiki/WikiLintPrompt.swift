import Foundation

/// Builds the LLM half of the wiki lint: a prompt embedding the SQL
/// findings plus the semantic checks only a model can do (contradictions,
/// stale claims, near-duplicates). The model *proposes* fixes and applies
/// them through visible `write_wiki_page` calls — nothing is auto-applied.
enum WikiLintPrompt {
    static func build(report: LintReport) -> String {
        var findings: [String] = []

        if !report.orphans.isEmpty {
            let list = report.orphans
                .map { "- \($0.title) (id: \($0.pageID))" }
                .joined(separator: "\n")
            findings.append("Pages orphelines (aucun lien entrant) :\n\(list)")
        }
        if !report.danglingLinks.isEmpty {
            let list = report.danglingLinks
                .map { "- [[\($0.dstTitleRaw)]] depuis « \($0.srcTitle) »" }
                .joined(separator: "\n")
            findings.append("Liens cassés (cible inexistante) :\n\(list)")
        }
        if !report.missingConcepts.isEmpty {
            let list = report.missingConcepts
                .map { "- « \($0.titleRaw) » (\($0.references) références)" }
                .joined(separator: "\n")
            findings.append("Concepts manquants (référencés plusieurs fois, aucune page) :\n\(list)")
        }

        let structural = findings.isEmpty
            ? "L'audit structurel n'a rien détecté."
            : findings.joined(separator: "\n\n")

        return """
        Fais un audit de santé du wiki. C'est un audit de la STRUCTURE du \
        wiki, pas une recherche de contenu : n'utilise pas `web_search`.

        Audit structurel (déjà calculé) :
        \(structural)

        À toi de faire la passe sémantique. Traite un problème à la fois, \
        et applique sa correction avec `write_wiki_page` avant de passer au \
        suivant (n'accumule pas les lectures) :
        1. Lis l'index (`read_page` id `index`) pour repérer les pages \
        proches ou anciennes.
        2. Pour chaque problème — contradiction entre pages, affirmation \
        probablement périmée (compare la date `updated`), ou deux pages sur \
        le même sujet — explique-le, puis corrige-le tout de suite : \
        `write_wiki_page` (fusionne les doublons dans la page la plus \
        complète). Ne relis pas une page déjà lue.
        3. Crée les pages des concepts manquants listés ci-dessus si tu as \
        assez de matière.

        Les conventions du wiki sont déjà dans ton contexte système.
        """
    }
}
