import Foundation
import Observation
import TaxonDomain
import TaxonSettings

@MainActor
@Observable
final class SearchModel {
    enum State: Equatable {
        case idle
        case loading
        case candidates([TaxonCandidate])
        case resolved(Taxon)
        case noMatch
        case failed(String)
    }

    var queryText = ""
    var state: State = .idle
    var configuredLanguages: [TaxonLanguage] {
        didSet { persistSettings() }
    }
    var scientificNamePosition: ScientificNamePosition {
        didSet { persistSettings() }
    }
    var preferredWikipediaLanguage: TaxonLanguage? {
        didSet { persistSettings() }
    }

    private let resolver: any TaxonResolving
    private let settingsStore: SharedOutputSettingsStore?
    private var searchTask: Task<Void, Never>?

    init(
        resolver: any TaxonResolving,
        configuredLanguages: [TaxonLanguage] = [
            TaxonLanguage(rawValue: "en")!,
            TaxonLanguage(rawValue: "fr")!,
            TaxonLanguage(rawValue: "nl")!
        ],
        scientificNamePosition: ScientificNamePosition = .last,
        preferredWikipediaLanguage: TaxonLanguage? = TaxonLanguage(rawValue: "en"),
        settingsStore: SharedOutputSettingsStore? = nil
    ) {
        let persistedSettings = settingsStore?.load()
        self.resolver = resolver
        self.settingsStore = settingsStore
        self.configuredLanguages = persistedSettings?.languages ?? configuredLanguages
        self.scientificNamePosition = persistedSettings?.scientificNamePosition ?? scientificNamePosition
        self.preferredWikipediaLanguage = persistedSettings?.preferredWikipediaLanguage ?? preferredWikipediaLanguage
    }

    var outputConfiguration: OutputLanguageConfiguration {
        OutputLanguageConfiguration(
            languages: configuredLanguages,
            scientificNamePosition: scientificNamePosition
        )
    }

    func searchTextDidChange() {
        searchTask?.cancel()
        guard let query = TaxonSearchQuery(queryText) else {
            // `dismissSearch()` may clear the searchable binding after a result
            // arrives. Keep that result visible; a new nonempty query will
            // replace it normally.
            if case .resolved = state { return }
            state = .idle
            return
        }

        state = .loading
        searchTask = Task { [weak self, resolver, configuredLanguages] in
            do {
                try await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                let resolution = try await resolver.resolve(query: query, languages: configuredLanguages)
                guard !Task.isCancelled else { return }
                self?.apply(resolution)
            } catch is CancellationError {
                // A newer query superseded this lookup.
            } catch let error as TaxonResolutionError {
                guard !Task.isCancelled else { return }
                self?.state = .failed(Self.message(for: error))
            } catch {
                guard !Task.isCancelled else { return }
                self?.state = .failed("Taxon lookup could not be completed.")
            }
        }
    }

    func resolveImmediately(_ text: String) async {
        searchTask?.cancel()
        queryText = text
        guard let query = TaxonSearchQuery(text) else {
            state = .idle
            return
        }
        state = .loading
        do {
            apply(try await resolver.resolve(query: query, languages: configuredLanguages))
        } catch let error as TaxonResolutionError {
            state = .failed(Self.message(for: error))
        } catch {
            state = .failed("Taxon lookup could not be completed.")
        }
    }

    func select(_ candidate: TaxonCandidate) {
        searchTask?.cancel()
        state = .resolved(candidate.taxon)
    }

    @discardableResult
    func addLanguage(input: String) async -> Bool {
        guard
            let language = TaxonLanguagePresentation.language(from: input),
            !configuredLanguages.contains(language)
        else {
            return false
        }
        configuredLanguages.append(language)

        guard case let .resolved(taxon) = state else { return true }
        do {
            if let refreshed = try await resolver.taxon(
                for: taxon.wikidataID,
                languages: configuredLanguages
            ) {
                state = .resolved(refreshed)
            }
        } catch {
            // Keep the existing result visible. A later lookup can retry the
            // newly configured language without discarding useful data.
        }
        return true
    }

    func removeLanguages(at offsets: IndexSet) {
        configuredLanguages.remove(atOffsets: offsets)
    }

    func moveLanguages(from source: IndexSet, to destination: Int) {
        configuredLanguages.move(fromOffsets: source, toOffset: destination)
    }

    private func apply(_ resolution: TaxonResolution) {
        switch resolution {
        case let .resolved(taxon): state = .resolved(taxon)
        case let .candidates(candidates): state = .candidates(candidates)
        case .noMatch: state = .noMatch
        }
    }

    private func persistSettings() {
        settingsStore?.save(OutputSettingsSnapshot(
            languages: configuredLanguages,
            scientificNamePosition: scientificNamePosition,
            preferredWikipediaLanguage: preferredWikipediaLanguage
        ))
    }

    private static func message(for error: TaxonResolutionError) -> String {
        switch error {
        case .networkUnavailable: return "No network connection is available."
        case .rateLimited: return "The naming source asked us to try again shortly."
        case .temporaryServerFailure: return "The naming source is temporarily unavailable."
        case .invalidProviderResponse: return "The naming source returned an unreadable response."
        }
    }
}
