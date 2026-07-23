import Foundation
import Testing
@testable import Taxon
import TaxonDomain
import TaxonSettings

@MainActor
struct SearchModelTests {
    @Test("Mock resolver returns the fixture taxon for an accented common name")
    func resolvesAccentedName() async {
        let model = SearchModel(resolver: MockTaxonResolver())

        await model.resolveImmediately("Bondrée apivore")

        guard case let .resolved(taxon) = model.state else {
            Issue.record("Expected a resolved fixture taxon")
            return
        }
        #expect(taxon.wikidataID.rawValue == "Q170466")
        #expect(taxon.scientificName.value == "Pernis apivorus")
    }

    @Test(
        "Mock resolver resolves scientific names across taxonomic groups",
        arguments: [
            ("Quercus robur", "Q165145"),
            ("Bellis perennis", "Q159297"),
            ("Vulpes vulpes", "Q8332"),
            ("Apis mellifera", "Q30034")
        ]
    )
    func resolvesScientificNamesAcrossTaxonomicGroups(
        scientificName: String,
        expectedWikidataID: String
    ) async {
        let model = SearchModel(resolver: MockTaxonResolver())

        await model.resolveImmediately(scientificName)

        guard case let .resolved(taxon) = model.state else {
            Issue.record("Expected \(scientificName) to resolve")
            return
        }
        #expect(taxon.wikidataID.rawValue == expectedWikidataID)
        #expect(taxon.scientificName.value == scientificName)
    }

    @Test("Mock resolver preserves ambiguity for prefix matches")
    func retainsAmbiguity() async {
        let model = SearchModel(resolver: MockTaxonResolver())

        await model.resolveImmediately("Passer")

        guard case let .candidates(candidates) = model.state else {
            Issue.record("Expected explicit candidate selection")
            return
        }
        #expect(candidates.count == 2)
    }

    @Test("Search dismissal preserves a result until a new query begins")
    func preservesResolvedStateWhenSearchDismissalClearsQuery() async {
        let model = SearchModel(resolver: MockTaxonResolver())

        await model.resolveImmediately("Bondrée apivore")
        guard case .resolved = model.state else {
            Issue.record("Expected the initial lookup to resolve")
            return
        }

        model.queryText = ""
        model.searchTextDidChange()
        guard case .resolved = model.state else {
            Issue.record("Expected search dismissal to preserve the resolved result")
            return
        }

        model.queryText = "Passer"
        model.searchTextDidChange()
        #expect(model.state == .loading)
    }

    @Test("Output language edits preserve order and ignore duplicates")
    func editsOutputLanguages() async {
        let model = SearchModel(resolver: MockTaxonResolver())

        await model.addLanguage(input: "de")
        await model.addLanguage(input: "DE")
        model.moveLanguages(from: IndexSet(integer: 3), to: 0)
        model.removeLanguages(at: IndexSet(integer: 1))

        #expect(model.configuredLanguages.map(\.rawValue) == ["de", "fr", "nl"])
    }

    @Test("Output setting edits persist and initialize the next model")
    func persistsOutputSettings() async {
        let suiteName = "SearchModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SharedOutputSettingsStore(userDefaults: defaults)
        let model = SearchModel(resolver: MockTaxonResolver(), settingsStore: store)

        await model.addLanguage(input: "de")
        model.moveLanguages(from: IndexSet(integer: 3), to: 0)
        model.removeLanguages(at: IndexSet(integer: 1))
        model.scientificNamePosition = .first
        model.preferredWikipediaLanguage = TaxonLanguage(rawValue: "de")

        let reloaded = SearchModel(resolver: MockTaxonResolver(), settingsStore: store)
        #expect(reloaded.configuredLanguages.map(\.rawValue) == ["de", "fr", "nl"])
        #expect(reloaded.scientificNamePosition == .first)
        #expect(reloaded.preferredWikipediaLanguage?.rawValue == "de")
    }

    @Test("Localized language input maps to a canonical code and displays capitalized")
    func acceptsLocalizedLanguageName() {
        let english = Locale(identifier: "en")

        let italian = TaxonLanguagePresentation.language(from: "Italian", locale: english)

        #expect(italian?.rawValue == "it")
        #expect(italian.map { TaxonLanguagePresentation.displayName(for: $0, locale: english) } == "Italian")
    }

    @Test("Adding Italian rehydrates an already resolved taxon")
    func rehydratesResolvedTaxonForAddedLanguage() async {
        let resolver = LanguageRefreshResolver()
        let model = SearchModel(
            resolver: resolver,
            configuredLanguages: [TaxonLanguage(rawValue: "en")!]
        )

        await model.resolveImmediately("Quercus robur")
        let added = await model.addLanguage(input: "it")

        #expect(added)
        #expect(model.configuredLanguages.map(\.rawValue) == ["en", "it"])
        guard case let .resolved(taxon) = model.state else {
            Issue.record("Expected the resolved taxon to remain visible")
            return
        }
        #expect(taxon.preferredName(for: TaxonLanguage(rawValue: "it")!)?.value == "Farnia")
    }
}

private struct LanguageRefreshResolver: TaxonResolving {
    private let identity = TaxonIdentity(
        wikidataID: WikidataID(rawValue: "Q165145")!,
        scientificName: ScientificName("Quercus robur")!
    )

    func resolve(
        query: TaxonSearchQuery,
        languages: [TaxonLanguage]
    ) async throws -> TaxonResolution {
        .resolved(taxon(languages: languages))
    }

    func taxon(
        for wikidataID: WikidataID,
        languages: [TaxonLanguage]
    ) async throws -> Taxon? {
        guard wikidataID == identity.wikidataID else { return nil }
        return taxon(languages: languages)
    }

    private func taxon(languages: [TaxonLanguage]) -> Taxon {
        let names = languages.compactMap { language -> LocalizedTaxonName? in
            switch language.baseLanguageCode {
            case "en":
                return LocalizedTaxonName(language: language, value: "English oak")
            case "it":
                return LocalizedTaxonName(language: language, value: "Farnia")
            default:
                return nil
            }
        }
        return Taxon(identity: identity, rank: TaxonomicRank("species"), names: names)
    }
}
