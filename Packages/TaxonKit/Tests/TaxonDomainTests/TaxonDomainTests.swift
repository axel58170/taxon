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

    @Test("Language values accept codes, not localized display names")
    func validatesLanguageCodes() {
        #expect(TaxonLanguage(rawValue: "Italian") == nil)
        #expect(TaxonLanguage(rawValue: "it_IT")?.rawValue == "it-IT")
        #expect(TaxonLanguage(rawValue: "IT_it")?.rawValue == "it-IT")
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

    @Test("Localized names capitalize only their first character for display and copying")
    func capitalizesLocalizedNameForPresentation() throws {
        let italian = try #require(TaxonLanguage(rawValue: "it"))
        let japanese = try #require(TaxonLanguage(rawValue: "ja"))

        #expect(LocalizedTaxonName(language: italian, value: "gruccione")?.displayValue == "Gruccione")
        #expect(LocalizedTaxonName(language: french, value: "guêpier d'Europe")?.displayValue == "Guêpier d'Europe")
        #expect(LocalizedTaxonName(language: japanese, value: "ヨーロッパハチクイ")?.displayValue == "ヨーロッパハチクイ")
    }

    @Test("Alternative names omit the preferred value and normalized duplicates in stable order")
    func selectsAlternativeNames() throws {
        let preferred = try #require(
            LocalizedTaxonName(
                language: dutch,
                value: "Gedomesticeerd rund",
                source: .wikidata,
                isPreferred: true
            )
        )
        let cow = try #require(
            LocalizedTaxonName(
                language: dutch,
                value: "koe",
                source: .catalogueOfLife,
                isPreferred: false
            )
        )
        let duplicateCow = try #require(
            LocalizedTaxonName(
                language: dutch,
                value: "KÓE",
                source: .wikidata,
                isPreferred: false
            )
        )
        let domesticatedCow = try #require(
            LocalizedTaxonName(
                language: dutch,
                value: "gedomesticeerde koe",
                source: .catalogueOfLife,
                isPreferred: false
            )
        )
        let englishName = try #require(
            LocalizedTaxonName(
                language: english,
                value: "Cow",
                source: .catalogueOfLife,
                isPreferred: false
            )
        )
        let taxon = makeTaxon(names: [
            cow,
            preferred,
            duplicateCow,
            domesticatedCow,
            englishName
        ])

        #expect(taxon.preferredName(for: dutch) == preferred)
        #expect(taxon.alternativeNames(for: dutch) == [cow, domesticatedCow])
        #expect(taxon.alternativeNames(for: french).isEmpty)
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
