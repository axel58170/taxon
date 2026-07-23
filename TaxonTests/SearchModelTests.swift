import Foundation
import Testing
@testable import Taxon
import TaxonDomain

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

    @Test("Output language edits preserve order and ignore duplicates")
    func editsOutputLanguages() {
        let model = SearchModel(resolver: MockTaxonResolver())

        model.addLanguage(code: "de")
        model.addLanguage(code: "DE")
        model.moveLanguages(from: IndexSet(integer: 3), to: 0)
        model.removeLanguages(at: IndexSet(integer: 1))

        #expect(model.configuredLanguages.map(\.rawValue) == ["de", "fr", "nl"])
    }
}
