import Foundation
import TaxonDomain

/// Deterministic development data. The app swaps this composition root for WikidataProvider later.
struct MockTaxonResolver: TaxonResolving {
    private let taxa: [Taxon] = [
        Self.makeTaxon(
            id: "Q170466",
            scientificName: "Pernis apivorus",
            rank: "species",
            names: [("en", "European Honey-buzzard"), ("fr", "Bondrée apivore"), ("nl", "Wespendief")],
            sitelinks: [("en", "European_honey_buzzard"), ("fr", "Bondrée_apivore"), ("nl", "Wespendief")]
        ),
        Self.makeTaxon(
            id: "Q25390",
            scientificName: "Passer domesticus",
            rank: "species",
            names: [("en", "House Sparrow"), ("fr", "Moineau domestique"), ("nl", "Huismus")],
            sitelinks: [("en", "House_sparrow"), ("fr", "Moineau_domestique")]
        ),
        Self.makeTaxon(
            id: "Q166354",
            scientificName: "Passer montanus",
            rank: "species",
            names: [("en", "Eurasian Tree Sparrow"), ("fr", "Moineau friquet"), ("nl", "Ringmus")],
            sitelinks: [("en", "Eurasian_tree_sparrow"), ("nl", "Ringmus")]
        ),
        Self.makeTaxon(
            id: "Q165145",
            scientificName: "Quercus robur",
            rank: "species",
            names: [("en", "Pedunculate Oak"), ("fr", "Chêne pédonculé"), ("nl", "Zomereik")],
            sitelinks: [("en", "Quercus_robur"), ("fr", "Chêne_pédonculé"), ("nl", "Zomereik")]
        ),
        Self.makeTaxon(
            id: "Q159297",
            scientificName: "Bellis perennis",
            rank: "species",
            names: [("en", "Common Daisy"), ("fr", "Pâquerette"), ("nl", "Madeliefje")],
            sitelinks: [("en", "Bellis_perennis"), ("fr", "Pâquerette"), ("nl", "Madeliefje")]
        ),
        Self.makeTaxon(
            id: "Q8332",
            scientificName: "Vulpes vulpes",
            rank: "species",
            names: [("en", "Red Fox"), ("fr", "Renard roux"), ("nl", "Vos")],
            sitelinks: [("en", "Red_fox"), ("fr", "Renard_roux"), ("nl", "Vos_(dier)")]
        ),
        Self.makeTaxon(
            id: "Q30034",
            scientificName: "Apis mellifera",
            rank: "species",
            names: [("en", "Western Honey Bee"), ("fr", "Abeille européenne"), ("nl", "Europese honingbij")],
            sitelinks: [("en", "Western_honey_bee"), ("fr", "Apis_mellifera"), ("nl", "Europese_honingbij")]
        )
    ]

    func resolve(query: TaxonSearchQuery, languages: [TaxonLanguage]) async throws -> TaxonResolution {
        let candidates = taxa.compactMap { taxon -> TaxonCandidate? in
            let scientific = TaxonSearchQuery.normalize(taxon.scientificName.value)
            if scientific == query.normalizedText {
                return TaxonCandidate(taxon: taxon, matchKind: .exactScientificName, matchedName: taxon.scientificName.value)
            }

            let matchingName = taxon.names.first {
                TaxonSearchQuery.normalize($0.value) == query.normalizedText
            }
            if let matchingName {
                return TaxonCandidate(taxon: taxon, matchKind: .exactLocalizedName, matchedName: matchingName.value)
            }

            let prefixName = ([taxon.scientificName.value] + taxon.names.map(\.value)).first {
                TaxonSearchQuery.normalize($0).hasPrefix(query.normalizedText)
            }
            guard let prefixName else { return nil }
            return TaxonCandidate(taxon: taxon, matchKind: .prefix, matchedName: prefixName)
        }.sorted { $0.matchKind < $1.matchKind }

        switch candidates.count {
        case 0: return .noMatch
        case 1: return .resolved(candidates[0].taxon)
        default: return .candidates(candidates)
        }
    }

    func taxon(for wikidataID: WikidataID, languages: [TaxonLanguage]) async throws -> Taxon? {
        taxa.first { $0.wikidataID == wikidataID }
    }

    private static func makeTaxon(
        id: String,
        scientificName: String,
        rank: String,
        names: [(String, String)],
        sitelinks: [(String, String)]
    ) -> Taxon {
        Taxon(
            identity: TaxonIdentity(
                wikidataID: WikidataID(rawValue: id)!,
                scientificName: ScientificName(scientificName)!
            ),
            rank: TaxonomicRank(rank),
            names: names.map { language, value in
                LocalizedTaxonName(language: TaxonLanguage(rawValue: language)!, value: value)!
            },
            wikipediaSitelinks: sitelinks.map { language, title in
                WikipediaSitelink(
                    language: TaxonLanguage(rawValue: language)!,
                    title: title.replacingOccurrences(of: "_", with: " "),
                    url: URL(string: "https://\(language).wikipedia.org/wiki/\(title)")!
                )!
            }
        )
    }
}
