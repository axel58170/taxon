import Testing
@testable import Taxon
import TaxonDomain

struct TaxonIntentFormattingTests {
    @Test("Entity adapter keeps the Q-ID identity and chooses the first configured localized name")
    func makesEntity() {
        let entity = TaxonEntity(taxon: honeyBuzzard, preferredLanguages: [french, english])

        #expect(entity.id == "Q170466")
        #expect(entity.localizedName == "Bondrée apivore")
        #expect(entity.scientificName == "Pernis apivorus")
    }

    @Test("Configured output keeps missing localized names explicit")
    func formatsNames() {
        let output = TaxonIntentFormatting.formattedNames(
            for: honeyBuzzard,
            configuration: OutputLanguageConfiguration(languages: [french, TaxonLanguage(rawValue: "de")!], scientificNamePosition: .first)
        )

        #expect(output == "Scientific: Pernis apivorus\nfr: Bondrée apivore\nde: Not available")
    }

    @Test("Candidate disambiguation titles remain unique")
    func makesCandidateTitlesUnique() {
        let candidates = [
            TaxonCandidate(taxon: honeyBuzzard, matchKind: .exactLocalizedName),
            TaxonCandidate(taxon: honeyBuzzard, matchKind: .exactLocalizedName)
        ]

        #expect(TaxonIntentFormatting.uniqueCandidateChoices(candidates).map(\.title) == [
            "Pernis apivorus · species",
            "Pernis apivorus · species [Q170466]"
        ])
    }

    private let english = TaxonLanguage(rawValue: "en")!
    private let french = TaxonLanguage(rawValue: "fr")!
    private let honeyBuzzard = Taxon(
        identity: TaxonIdentity(
            wikidataID: WikidataID(rawValue: "Q170466")!,
            scientificName: ScientificName("Pernis apivorus")!
        ),
        rank: TaxonomicRank("species"),
        names: [
            LocalizedTaxonName(language: TaxonLanguage(rawValue: "en")!, value: "European Honey-buzzard")!,
            LocalizedTaxonName(language: TaxonLanguage(rawValue: "fr")!, value: "Bondrée apivore")!
        ]
    )
}
