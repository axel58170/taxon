import AppIntents
import Foundation
import TaxonDomain
import TaxonSettings

/// The app-owned adapter between App Intents and the reusable resolver boundary.
final class TaxonIntentService: Sendable {
    let resolver: any TaxonResolving
    let settingsStore: SharedOutputSettingsStore

    init(
        resolver: any TaxonResolving,
        settingsStore: SharedOutputSettingsStore
    ) {
        self.resolver = resolver
        self.settingsStore = settingsStore
    }

    func resolve(_ text: String) async throws -> (resolution: TaxonResolution, settings: OutputSettingsSnapshot) {
        guard let query = TaxonSearchQuery(text) else { throw TaxonIntentError.emptyQuery }
        let settings = settingsStore.load()
        let resolution = try await resolver.resolve(query: query, languages: settings.languages)
        return (resolution, settings)
    }

    func taxon(for id: String) async throws -> (taxon: Taxon?, settings: OutputSettingsSnapshot) {
        let settings = settingsStore.load()
        guard let wikidataID = WikidataID(rawValue: id) else { return (nil, settings) }
        let taxon = try await resolver.taxon(for: wikidataID, languages: settings.languages)
        return (taxon, settings)
    }
}

struct TaxonEntity: AppEntity, Hashable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Taxon")
    static let defaultQuery = TaxonEntityQuery()

    let id: String
    let scientificName: String
    let localizedName: String?
    let rankName: String?

    init(taxon: Taxon, preferredLanguages: [TaxonLanguage] = TaxonIntentFormatting.defaultLanguages) {
        id = taxon.wikidataID.rawValue
        scientificName = taxon.scientificName.value
        localizedName = TaxonIntentFormatting.displayName(for: taxon, preferredLanguages: preferredLanguages)
        rankName = taxon.rank?.name
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(localizedName ?? scientificName)",
            subtitle: "\(scientificName)\(rankName.map { " · \($0)" } ?? "")"
        )
    }
}

struct TaxonEntityQuery: EntityStringQuery {
    @Dependency private var service: TaxonIntentService

    func entities(for identifiers: [TaxonEntity.ID]) async throws -> [TaxonEntity] {
        var entities: [TaxonEntity] = []
        for identifier in identifiers {
            let result = try await service.taxon(for: identifier)
            if let taxon = result.taxon {
                entities.append(TaxonEntity(taxon: taxon, preferredLanguages: result.settings.languages))
            }
        }
        return entities
    }

    func entities(matching string: String) async throws -> [TaxonEntity] {
        let result = try await service.resolve(string)
        switch result.resolution {
        case let .resolved(taxon):
            return [TaxonEntity(taxon: taxon, preferredLanguages: result.settings.languages)]
        case let .candidates(candidates):
            return candidates.map { TaxonEntity(taxon: $0.taxon, preferredLanguages: result.settings.languages) }
        case .noMatch:
            return []
        }
    }

    func suggestedEntities() async throws -> [TaxonEntity] { [] }
}

struct ResolveTaxonIntent: AppIntent {
    static let title: LocalizedStringResource = "Resolve Taxon"
    static let description = IntentDescription("Resolve a common or scientific name to a taxon.")

    @Parameter(title: "Name") var name: String
    @Dependency private var service: TaxonIntentService

    init() {}

    init(name: String) {
        self.name = name
    }

    func perform() async throws -> some IntentResult & ReturnsValue<TaxonEntity> {
        let result = try await service.resolve(name)
        switch result.resolution {
        case let .resolved(taxon):
            return .result(value: TaxonEntity(taxon: taxon, preferredLanguages: result.settings.languages))
        case let .candidates(candidates):
            let choices = TaxonIntentFormatting.uniqueCandidateChoices(candidates)
            let selectedChoice = try await $name.requestDisambiguation(
                among: choices.map(\.title),
                dialog: IntentDialog("Which taxon do you mean?")
            )
            guard let selected = choices.first(where: { $0.title == selectedChoice })?.candidate else {
                throw TaxonIntentError.selectionUnavailable
            }
            return .result(value: TaxonEntity(taxon: selected.taxon, preferredLanguages: result.settings.languages))
        case .noMatch:
            throw TaxonIntentError.noMatchingTaxon
        }
    }
}

struct GetTaxonNameIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Taxon Name"
    static let description = IntentDescription("Get one localized name for a taxon.")

    @Parameter(title: "Taxon") var taxon: TaxonEntity
    @Parameter(title: "Language") var language: String
    @Dependency private var service: TaxonIntentService

    init() {}

    init(taxon: TaxonEntity, language: String) {
        self.taxon = taxon
        self.language = language
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let language = TaxonLanguage(rawValue: language) else { throw TaxonIntentError.invalidLanguage }
        guard let resolvedTaxon = try await service.taxon(for: taxon.id).taxon else { throw TaxonIntentError.noMatchingTaxon }
        guard let name = resolvedTaxon.preferredName(for: language)?.displayValue else { throw TaxonIntentError.nameUnavailable }
        return .result(value: name)
    }
}

struct GetConfiguredTaxonNamesIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Configured Taxon Names"

    @Parameter(title: "Taxon") var taxon: TaxonEntity
    @Dependency private var service: TaxonIntentService

    init() {}

    init(taxon: TaxonEntity) {
        self.taxon = taxon
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let result = try await service.taxon(for: taxon.id)
        guard let resolvedTaxon = result.taxon else { throw TaxonIntentError.noMatchingTaxon }
        let configuration = OutputLanguageConfiguration(
            languages: result.settings.languages,
            scientificNamePosition: result.settings.scientificNamePosition
        )
        return .result(value: TaxonIntentFormatting.formattedNames(for: resolvedTaxon, configuration: configuration))
    }
}

@available(iOS 18.0, *)
struct OpenTaxonInWikipediaIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Taxon in Wikipedia"

    @Parameter(title: "Taxon") var taxon: TaxonEntity
    @Parameter(title: "Wikipedia Language", default: nil) var language: String?
    @Dependency private var service: TaxonIntentService

    init() {}

    init(taxon: TaxonEntity, language: String? = nil) {
        self.taxon = taxon
        self.language = language
    }

    func perform() async throws -> some IntentResult & OpensIntent {
        if let language, TaxonLanguage(rawValue: language) == nil { throw TaxonIntentError.invalidLanguage }
        let result = try await service.taxon(for: taxon.id)
        guard let resolvedTaxon = result.taxon else { throw TaxonIntentError.noMatchingTaxon }
        let preferredLanguage = language.flatMap { TaxonLanguage(rawValue: $0) } ?? result.settings.preferredWikipediaLanguage
        guard let sitelink = resolvedTaxon.wikipediaSitelink(
            preferredLanguage: preferredLanguage,
            configuredLanguages: result.settings.languages
        ) else {
            throw TaxonIntentError.wikipediaUnavailable
        }
        return .result(opensIntent: OpenURLIntent(sitelink.url))
    }
}

struct TaxonShortcuts: AppShortcutsProvider {
    static let shortcutTileColor: ShortcutTileColor = .teal

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ResolveTaxonIntent(),
            phrases: [
                "Resolve a taxon in \(.applicationName)",
                "Find a taxon with \(.applicationName)"
            ],
            shortTitle: "Resolve Taxon",
            systemImageName: "leaf"
        )
        AppShortcut(
            intent: GetTaxonNameIntent(),
            phrases: [
                "Get a name for \(\.$taxon) in \(.applicationName)"
            ],
            shortTitle: "Get Taxon Name",
            systemImageName: "character.book.closed"
        )
        AppShortcut(
            intent: GetConfiguredTaxonNamesIntent(),
            phrases: [
                "Get configured names for \(\.$taxon) in \(.applicationName)"
            ],
            shortTitle: "Get Taxon Names",
            systemImageName: "list.bullet"
        )
    }
}

enum TaxonIntentFormatting {
    static let defaultLanguages = [
        TaxonLanguage(rawValue: "en")!,
        TaxonLanguage(rawValue: "fr")!,
        TaxonLanguage(rawValue: "nl")!
    ]

    static func displayName(for taxon: Taxon, preferredLanguages: [TaxonLanguage]) -> String? {
        for language in preferredLanguages {
            if let name = taxon.preferredName(for: language)?.displayValue { return name }
        }
        return nil
    }

    static func formattedNames(for taxon: Taxon, configuration: OutputLanguageConfiguration) -> String {
        configuration.displayRows(for: taxon).map { row in
            switch row {
            case let .scientific(name):
                return "\(String(localized: "Scientific")): \(name.value)"
            case let .localized(language, name):
                return "\(language.rawValue): \(name?.displayValue ?? String(localized: "Not available"))"
            }
        }.joined(separator: "\n")
    }

    static func uniqueCandidateChoices(_ candidates: [TaxonCandidate]) -> [(title: String, candidate: TaxonCandidate)] {
        var used = Set<String>()
        return candidates.compactMap { candidate in
            let base = [candidate.taxon.scientificName.value, candidate.taxon.rank?.name]
                .compactMap { $0 }
                .joined(separator: " · ")
            let title = used.insert(base).inserted ? base : "\(base) [\(candidate.taxon.wikidataID.rawValue)]"
            return (title, candidate)
        }
    }
}

enum TaxonIntentError: Error, LocalizedError {
    case emptyQuery
    case noMatchingTaxon
    case selectionUnavailable
    case invalidLanguage
    case nameUnavailable
    case wikipediaUnavailable

    var errorDescription: String? {
        switch self {
        case .emptyQuery: return String(localized: "Enter a common or scientific taxon name.")
        case .noMatchingTaxon: return String(localized: "No matching taxon was found.")
        case .selectionUnavailable: return String(localized: "The selected taxon is no longer available.")
        case .invalidLanguage: return String(localized: "Enter a valid language code, such as en or fr.")
        case .nameUnavailable: return String(localized: "That name is not available in the requested language.")
        case .wikipediaUnavailable: return String(localized: "No Wikipedia article is available for this taxon.")
        }
    }
}
