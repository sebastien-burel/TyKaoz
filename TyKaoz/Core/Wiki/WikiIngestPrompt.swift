import Foundation

/// The ingest instruction sent through the normal chat loop when the user
/// asks to wikify a source. Scope is capped at a few pages — Karpathy's
/// pattern says a source can touch 10-15, but ChatSession.maxToolRounds
/// bounds the loop and small local models degrade well before that.
enum WikiIngestPrompt {
    static func build(sourceID: String) -> String {
        """
        Ingère la source `\(sourceID)` dans le wiki :
        1. Lis-la avec `read_source` (id : `\(sourceID)`).
        2. Écris une page de type `resume-source` qui en synthétise \
        l'essentiel, avec `sources: [\(sourceID)]` dans le frontmatter.
        3. Crée ou mets à jour AU MAXIMUM 5 pages d'entités ou de concepts \
        importants mentionnés dans la source — `search_wiki` d'abord pour \
        éviter les doublons.

        Règles pour rester efficace (tu as un budget de tours limité) :
        - Écris chaque page COMPLÈTE et définitive du premier coup, liens \
        `[[…]]` compris. Tu peux lier vers des pages que tu crées dans ce \
        même tour : les liens se résolvent une fois toutes les pages écrites.
        - Ne réécris JAMAIS une page que tu viens d'écrire, et ne relis pas \
        une page déjà lue.
        - Reste sur cette source : n'utilise pas `web_search`, et ne lance \
        pas `lint_wiki` (l'utilisateur le fera séparément).
        Les conventions du wiki sont déjà dans ton contexte système.
        """
    }
}
