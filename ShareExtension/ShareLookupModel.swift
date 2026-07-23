import Foundation
import Observation
import TaxonDomain
import TaxonSettings

@MainActor
@Observable
final class ShareLookupModel {
    enum State: Equatable {
        case loadingInput
        case resolving
        case candidates([TaxonCandidate])
        case resolved(Taxon)
        case noMatch
        case failed(String)
    }

    private(set) var state: State = .loadingInput
    let settings: OutputSettingsSnapshot
    private let resolver: any TaxonResolving

    init(resolver: any TaxonResolving, settings: OutputSettingsSnapshot) {
        self.resolver = resolver
        self.settings = settings
    }

    var outputConfiguration: OutputLanguageConfiguration {
        OutputLanguageConfiguration(
            languages: settings.languages,
            scientificNamePosition: settings.scientificNamePosition
        )
    }

    func resolve(_ text: String) async {
        guard let query = TaxonSearchQuery(text) else {
            state = .failed("The shared item does not contain a taxon name.")
            return
        }
        state = .resolving
        do {
            switch try await resolver.resolve(query: query, languages: settings.languages) {
            case let .resolved(taxon): state = .resolved(taxon)
            case let .candidates(candidates): state = .candidates(candidates)
            case .noMatch: state = .noMatch
            }
        } catch let error as TaxonResolutionError {
            state = .failed(Self.message(for: error))
        } catch {
            state = .failed("Taxon lookup could not be completed.")
        }
    }

    func select(_ candidate: TaxonCandidate) {
        state = .resolved(candidate.taxon)
    }

    func failToLoadInput() {
        state = .failed("Taxon could not read plain text from the shared item.")
    }

    private static func message(for error: TaxonResolutionError) -> String {
        switch error {
        case .networkUnavailable: return "No network connection is available."
        case .rateLimited: return "Wikidata asked Taxon to try again shortly."
        case .temporaryServerFailure: return "Wikidata is temporarily unavailable."
        case .invalidProviderResponse: return "Wikidata returned an unreadable response."
        }
    }
}
