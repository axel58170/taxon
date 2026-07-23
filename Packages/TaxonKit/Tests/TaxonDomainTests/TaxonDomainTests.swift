import Foundation
import Testing
@testable import TaxonDomain

struct TaxonDomainTests {
    private let dutch = TaxonLanguage(rawValue: "nl")!
    private let english = TaxonLanguage(rawValue: "en")!
    private let french = TaxonLanguage(rawValue: "fr")!

    @Test("Query normalization trims, collapses whitespace, and ignores accents and case")
    func normalizesQuery() {
        let query = TaxonSearchQuery("  Bondrée   APIVORE  ")

        #expect(query?.originalText == "Bondrée   APIVORE")
        #expect(query?.normalizedText == "bondree apivore")
        #expect(TaxonSearchQuery.normalize("WESPENDIEF") == "wespendief")
    }

    @Test("Blank query is rejected")
    func rejectsBlankQuery() {
        #expect(TaxonSearchQuery(" \n\t ") == nil)
    }

    @Test("Configured ordering preserves a missing language row and the scientific position")
    func createsOutputRows() {
        let taxon = makeTaxon(names: [
            LocalizedTaxonName(language: dutch, value: "Wespendief")!,
            LocalizedTaxonName(language: english, value: "European Honey-buzzard")!
        ])
        let configuration = OutputLanguageConfiguration(
            languages: [french, dutch, english, dutch],
            scientificNamePosition: .first
        )

        #expect(configuration.languages == [french, dutch, english])
        #expect(configuration.displayRows(for: taxon) == [
            .scientific(ScientificName("Pernis apivorus")!),
            .localized(language: french, name: nil),
            .localized(language: dutch, name: LocalizedTaxonName(language: dutch, value: "Wespendief")!),
            .localized(language: english, name: LocalizedTaxonName(language: english, value: "European Honey-buzzard")!)
        ])
    }

    @Test("Wikipedia chooses an actual preferred sitelink, then configured languages, then a stable fallback")
    func choosesWikipediaFallback() throws {
        let de = TaxonLanguage(rawValue: "de")!
        let taxon = makeTaxon(sitelinks: [
            try sitelink(language: english, title: "European honey buzzard"),
            try sitelink(language: dutch, title: "Wespendief")
        ])

        #expect(taxon.wikipediaSitelink(preferredLanguage: dutch, configuredLanguages: [english])?.language == dutch)
        #expect(taxon.wikipediaSitelink(preferredLanguage: french, configuredLanguages: [english, dutch])?.language == english)
        #expect(taxon.wikipediaSitelink(preferredLanguage: de, configuredLanguages: [french])?.language == english)
    }

    @Test("Canonical identity requires Q-ID and scientific name")
    func validatesIdentity() {
        #expect(WikidataID(rawValue: "q25443")?.rawValue == "Q25443")
        #expect(WikidataID(rawValue: "P225") == nil)
        #expect(ScientificName("   ") == nil)
    }

    private func makeTaxon(
        names: [LocalizedTaxonName] = [],
        sitelinks: [WikipediaSitelink] = []
    ) -> Taxon {
        Taxon(
            identity: TaxonIdentity(
                wikidataID: WikidataID(rawValue: "Q25443")!,
                scientificName: ScientificName("Pernis apivorus")!
            ),
            rank: TaxonomicRank("species"),
            names: names,
            wikipediaSitelinks: sitelinks
        )
    }

    private func sitelink(language: TaxonLanguage, title: String) throws -> WikipediaSitelink {
        let url = try #require(URL(string: "https://\(language.rawValue).wikipedia.org/wiki/\(title.replacingOccurrences(of: " ", with: "_"))"))
        return try #require(WikipediaSitelink(
            language: language,
            title: title,
            url: url
        ))
    }
}
