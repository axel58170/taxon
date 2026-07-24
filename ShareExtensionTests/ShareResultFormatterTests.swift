import Foundation
import Testing
import TaxonDomain

struct ShareResultFormatterTests {
    @Test("Rows preserve configured language order, missing values, and scientific position")
    func buildsRows() {
        let configuration = OutputLanguageConfiguration(
            languages: [TaxonLanguage(rawValue: "fr")!, TaxonLanguage(rawValue: "de")!],
            scientificNamePosition: .last
        )

        let rows = ShareResultFormatter.rows(for: taxon, configuration: configuration)

        #expect(rows.map(\.label) == ["fr", "de", "Scientific"])
        #expect(rows.map(\.value) == ["Bondrée apivore", nil, "Pernis apivorus"])
        #expect(rows.map(\.alternativeNamesText) == ["Busard apivore, Buse bondrée", nil, nil])
    }

    @Test("Copy-all formatting excludes unavailable rows")
    func formatsAvailableRows() {
        let rows = [
            ShareResultRow(
                id: "fr",
                label: "fr",
                value: "Bondrée apivore",
                alternativeNamesText: "Busard apivore, Buse bondrée",
                isScientific: false
            ),
            ShareResultRow(
                id: "de",
                label: "de",
                value: nil,
                alternativeNamesText: nil,
                isScientific: false
            ),
            ShareResultRow(
                id: "scientific",
                label: "Scientific",
                value: "Pernis apivorus",
                alternativeNamesText: nil,
                isScientific: true
            )
        ]

        #expect(ShareResultFormatter.formattedAvailableRows(rows) == "fr: Bondrée apivore\nScientific: Pernis apivorus")
    }

    private let taxon = Taxon(
        identity: TaxonIdentity(
            wikidataID: WikidataID(rawValue: "Q170466")!,
            scientificName: ScientificName("Pernis apivorus")!
        ),
        rank: TaxonomicRank("species"),
        names: [
            LocalizedTaxonName(
                language: TaxonLanguage(rawValue: "fr")!,
                value: "Bondrée apivore"
            )!,
            LocalizedTaxonName(
                language: TaxonLanguage(rawValue: "fr")!,
                value: "busard apivore",
                source: .catalogueOfLife,
                isPreferred: false
            )!,
            LocalizedTaxonName(
                language: TaxonLanguage(rawValue: "fr")!,
                value: "buse bondrée",
                source: .wikidata,
                isPreferred: false
            )!
        ]
    )
}
