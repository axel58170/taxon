import AppIntents
import Foundation
import TaxonDomain

/// The app-owned adapter between App Intents and the reusable resolver boundary.
/// It keeps output-language defaults in one explicit composition point until settings persist.
final class TaxonIntentService: Sendable {
    let resolver: any TaxonResolving
    let configuredLanguages: [TaxonLanguage]
    let scientificNamePosition: ScientificNamePosition
    let preferredWikipediaLanguage: TaxonLanguage?

    init(
        resolver: any TaxonResolving,
        configuredLanguages: [TaxonLanguage] = TaxonIntentFormatting.defaultLanguages,
        scientificNamePosition: ScientificNamePosition = .last,
        preferredWikipediaLanguage: TaxonLanguage? = TaxonLanguage(rawValue: "en")
    ) {
        self.resolver = resolver
        self.configuredLanguages = configuredLanguages
        self.scientificNamePosition = scientificNamePosition
        self.preferredWikipediaLanguage = preferredWikipediaLanguage
    }

    func resolve(_ text: String) async throws -> TaxonResolution {
        guard let query = TaxonSearchQuery(text) else { throw TaxonIntentError.emptyQuery }
        return try await resolver.resolve(query: query, languages: configuredLanguages)
    }

    func taxon(for id: String) async throws -> Taxon? {
        guard let wikidataID = WikidataID(rawValue: id) else { return nil }
        return try await resolver.taxon(for: wikidataID, languages: configuredLanguages)
    }

    var outputConfiguration: OutputLanguageConfiguration {
        OutputLanguageConfiguration(
            languages: configuredLanguages,
            scientificNamePosition: scientificNamePosition
        )
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
            if let taxon = try await service.taxon(for: identifier) {
                entities.append(TaxonEntity(taxon: taxon, preferredLanguages: service.configuredLanguages))
            }
        }
        return entities
    }

    func entities(matching string: String) async throws -> [TaxonEntity] {
        switch try await service.resolve(string) {
        case let .resolved(taxon):
            return [TaxonEntity(taxon: taxon, preferredLanguages: service.configuredLanguages)]
        case let .candidates(candidates):
            return candidates.map { TaxonEntity(taxon: $0.taxon, preferredLanguages: service.configuredLanguages) }
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
        switch try await service.resolve(name) {
        case let .resolved(taxon):
            return .result(value: TaxonEntity(taxon: taxon, preferredLanguages: service.configuredLanguages))
        case let .candidates(candidates):
            let choices = TaxonIntentFormatting.uniqueCandidateChoices(candidates)
            let selectedChoice = try await $name.requestDisambiguation(
                among: choices.map(\.title),
                dialog: IntentDialog("Which taxon do you mean?")
            )
            guard let selected = choices.first(where: { $0.title == selectedChoice })?.candidate else {
                throw TaxonIntentError.selectionUnavailable
            }
            return .result(value: TaxonEntity(taxon: selected.taxon, preferredLanguages: service.configuredLanguages))
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
        guard let resolvedTaxon = try await service.taxon(for: taxon.id) else { throw TaxonIntentError.noMatchingTaxon }
        guard let name = resolvedTaxon.preferredName(for: language)?.value else { throw TaxonIntentError.nameUnavailable }
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
        guard let resolvedTaxon = try await service.taxon(for: taxon.id) else { throw TaxonIntentError.noMatchingTaxon }
        return .result(value: TaxonIntentFormatting.formattedNames(for: resolvedTaxon, configuration: service.outputConfiguration))
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
        guard let resolvedTaxon = try await service.taxon(for: taxon.id) else { throw TaxonIntentError.noMatchingTaxon }
        let preferredLanguage = language.flatMap { TaxonLanguage(rawValue: $0) } ?? service.preferredWikipediaLanguage
        guard let sitelink = resolvedTaxon.wikipediaSitelink(
            preferredLanguage: preferredLanguage,
            configuredLanguages: service.configuredLanguages
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
            phrases: ["Resolve taxon in \(.applicationName)"],
            shortTitle: "Resolve Taxon",
            systemImageName: "leaf"
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
            if let name = taxon.preferredName(for: language)?.value { return name }
        }
        return nil
    }

    static func formattedNames(for taxon: Taxon, configuration: OutputLanguageConfiguration) -> String {
        configuration.displayRows(for: taxon).map { row in
            switch row {
            case let .scientific(name): return "Scientific: \(name.value)"
            case let .localized(language, name):
                return "\(language.rawValue): \(name?.value ?? "Not available")"
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
        case .emptyQuery: return "Enter a common or scientific taxon name."
        case .noMatchingTaxon: return "No matching taxon was found."
        case .selectionUnavailable: return "The selected taxon is no longer available."
        case .invalidLanguage: return "Enter a valid language code, such as en or fr."
        case .nameUnavailable: return "That name is not available in the requested language."
        case .wikipediaUnavailable: return "No Wikipedia article is available for this taxon."
        }
    }
}
