import Foundation
import Testing
@testable import TyKaoz

@Suite
struct WikilinkNormalizerTests {

    private static let registry: [String: String] = [
        "Phase 6": "phase-6",
        "Page 2": "p2",
        "Sébastien Burel": "person-sb"
    ]

    private static func resolve(_ raw: String) -> String? {
        registry[raw]
    }

    @Test
    func bareTitleResolvedToIDForm() {
        let body = "Voir [[Phase 6]]."
        let out = WikilinkNormalizer.normalize(body, resolve: Self.resolve)
        #expect(out == "Voir [[phase-6|Phase 6]].")
    }

    @Test
    func unresolvedTitlePassedThrough() {
        let body = "Voir [[Inconnue]]."
        let out = WikilinkNormalizer.normalize(body, resolve: Self.resolve)
        #expect(out == "Voir [[Inconnue]].")
    }

    @Test
    func aliasFormUntouched() {
        let body = "Voir [[phase-6|Alias custom]]."
        let out = WikilinkNormalizer.normalize(body, resolve: Self.resolve)
        #expect(out == "Voir [[phase-6|Alias custom]].")
    }

    @Test
    func multipleLinksOnSameLine() {
        let body = "[[Phase 6]] et [[Page 2]] avec [[Inconnue]]."
        let out = WikilinkNormalizer.normalize(body, resolve: Self.resolve)
        #expect(out == "[[phase-6|Phase 6]] et [[p2|Page 2]] avec [[Inconnue]].")
    }

    @Test
    func isIdempotent() {
        let body = "[[Phase 6]] et [[Page 2]]."
        let first = WikilinkNormalizer.normalize(body, resolve: Self.resolve)
        let second = WikilinkNormalizer.normalize(first, resolve: Self.resolve)
        #expect(first == second)
    }

    @Test
    func accentsAndPunctuationInTitleResolveCleanly() {
        let body = "Cf. [[Sébastien Burel]] pour les détails."
        let out = WikilinkNormalizer.normalize(body, resolve: Self.resolve)
        #expect(out == "Cf. [[person-sb|Sébastien Burel]] pour les détails.")
    }
}
