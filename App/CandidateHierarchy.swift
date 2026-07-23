import Foundation
import TaxonDomain

enum CandidateHierarchy {
    enum Kind: Int, CaseIterable, Sendable {
        case species
        case infraspecific
        case other
    }

    struct Section: Identifiable, Sendable {
        let kind: Kind
        let candidates: [TaxonCandidate]

        var id: Kind { kind }
    }

    static func sections(for candidates: [TaxonCandidate]) -> [Section] {
        let grouped = Dictionary(grouping: candidates, by: kind(for:))
        return Kind.allCases.compactMap { kind in
            guard let candidates = grouped[kind], !candidates.isEmpty else { return nil }
            return Section(kind: kind, candidates: candidates)
        }
    }

    private static func kind(for candidate: TaxonCandidate) -> Kind {
        let rank = candidate.taxon.rank?.name
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)

        switch rank {
        case "species":
            return .species
        case "subspecies", "variety", "form", "cultivar":
            return .infraspecific
        default:
            return .other
        }
    }
}
