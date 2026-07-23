import Testing
@testable import Taxon
import TaxonDomain

struct CandidateHierarchyTests {
    @Test("Species precede infraspecific taxa and other ranks")
    func ordersHierarchySections() {
        let candidates = [
            candidate(id: "Q1", name: "Apis", rank: "genus"),
            candidate(id: "Q2", name: "Apis mellifera ligustica", rank: "subspecies"),
            candidate(id: "Q3", name: "Apis mellifera", rank: "species")
        ]

        let sections = CandidateHierarchy.sections(for: candidates)

        #expect(sections.map(\.kind) == [.species, .infraspecific, .other])
        #expect(sections.flatMap(\.candidates).map(\.taxon.wikidataID.rawValue) == ["Q3", "Q2", "Q1"])
    }

    @Test("Provider ordering is preserved within each hierarchy level")
    func preservesProviderOrderWithinSections() {
        let candidates = [
            candidate(id: "Q11", name: "First species", rank: "species"),
            candidate(id: "Q21", name: "First subspecies", rank: "subspecies"),
            candidate(id: "Q12", name: "Second species", rank: "species"),
            candidate(id: "Q22", name: "Second variety", rank: "variety")
        ]

        let sections = CandidateHierarchy.sections(for: candidates)

        #expect(sections[0].candidates.map(\.taxon.wikidataID.rawValue) == ["Q11", "Q12"])
        #expect(sections[1].candidates.map(\.taxon.wikidataID.rawValue) == ["Q21", "Q22"])
    }

    @Test("Rank classification is case and diacritic insensitive")
    func normalizesRankNames() {
        let sections = CandidateHierarchy.sections(for: [
            candidate(id: "Q31", name: "Normalized species", rank: "Spécies"),
            candidate(id: "Q32", name: "Normalized form", rank: "FÓRM")
        ])

        #expect(sections.map(\.kind) == [.species, .infraspecific])
    }

    @Test("Unknown and missing ranks share the final section")
    func groupsOtherRanksLast() {
        let sections = CandidateHierarchy.sections(for: [
            candidate(id: "Q41", name: "Unknown rank", rank: "strain"),
            candidate(id: "Q42", name: "Missing rank", rank: nil)
        ])

        #expect(sections.map(\.kind) == [.other])
        #expect(sections[0].candidates.map(\.taxon.wikidataID.rawValue) == ["Q41", "Q42"])
    }

    private func candidate(
        id: String,
        name: String,
        rank: String?
    ) -> TaxonCandidate {
        TaxonCandidate(
            taxon: Taxon(
                identity: TaxonIdentity(
                    wikidataID: WikidataID(rawValue: id)!,
                    scientificName: ScientificName(name)!
                ),
                rank: rank.flatMap(TaxonomicRank.init)
            ),
            matchKind: .exactScientificName
        )
    }
}
