import Foundation

/// A validated Wikidata entity identifier. This is Taxon's canonical application identifier.
public struct WikidataID: RawRepresentable, Codable, Hashable, Sendable, Identifiable, Comparable {
    public let rawValue: String

    public var id: String { rawValue }

    public init?(rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard trimmed.range(of: #"^Q[1-9][0-9]*$"#, options: .regularExpression) != nil else {
            return nil
        }
        self.rawValue = trimmed
    }

    public static func < (lhs: WikidataID, rhs: WikidataID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// The portable scientific name paired with a `WikidataID` to identify a taxon.
public struct ScientificName: Codable, Hashable, Sendable {
    public let value: String

    public init?(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        self.value = trimmed
    }

}

/// The identifiers that are canonical to Taxon. Source-specific identifiers belong in provider modules.
public struct TaxonIdentity: Codable, Hashable, Sendable {
    public let wikidataID: WikidataID
    public let scientificName: ScientificName

    public init(wikidataID: WikidataID, scientificName: ScientificName) {
        self.wikidataID = wikidataID
        self.scientificName = scientificName
    }
}

/// A source label, intentionally without a provider-specific record identifier.
public struct NameSource: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static let wikidata = NameSource(rawValue: "wikidata")
}

/// A language understood by the configured naming source, expressed as a BCP-47-style tag.
public struct TaxonLanguage: RawRepresentable, Codable, Hashable, Sendable, Comparable, Identifiable {
    public let rawValue: String

    public var id: String { rawValue }

    public init?(rawValue: String) {
        let normalized = Self.normalize(rawValue)
        guard
            let baseCode = normalized.split(separator: "-", maxSplits: 1).first.map(String.init),
            Self.isoLanguageCodes.contains(baseCode)
        else {
            return nil
        }
        self.rawValue = normalized
    }

    public var baseLanguageCode: String {
        rawValue.split(separator: "-", maxSplits: 1).first.map(String.init) ?? rawValue
    }

    public static func < (lhs: TaxonLanguage, rhs: TaxonLanguage) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    private static func normalize(_ value: String) -> String {
        let pieces = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-", omittingEmptySubsequences: true)
        guard let first = pieces.first else { return "" }
        let subtags = pieces.dropFirst().map { piece -> String in
            let value = String(piece)
            if value.count == 4, value.allSatisfy(\.isLetter) {
                return value.prefix(1).uppercased() + value.dropFirst().lowercased()
            }
            if (value.count == 2 && value.allSatisfy(\.isLetter))
                || (value.count == 3 && value.allSatisfy(\.isNumber)) {
                return value.uppercased()
            }
            return value.lowercased()
        }
        return ([String(first).lowercased()] + subtags).joined(separator: "-")
    }

    private static let isoLanguageCodes = Set(
        Locale.LanguageCode.isoLanguageCodes.map { $0.identifier.lowercased() }
    )
}

/// A user-facing name for a taxon. It is not an alternate identity for the taxon.
public struct LocalizedTaxonName: Codable, Hashable, Sendable, Identifiable {
    public let language: TaxonLanguage
    public let value: String
    public let source: NameSource
    public let regionCode: String?
    public let isPreferred: Bool

    public var id: String { "\(language.rawValue)|\(value)|\(regionCode ?? "")" }

    public init?(
        language: TaxonLanguage,
        value: String,
        source: NameSource = .wikidata,
        regionCode: String? = nil,
        isPreferred: Bool = true
    ) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        self.language = language
        self.value = trimmed
        self.source = source
        self.regionCode = regionCode?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.isPreferred = isPreferred
    }
}

/// A rank supplied as text so the domain can preserve unfamiliar or future taxonomic ranks.
public struct TaxonomicRank: Codable, Hashable, Sendable, Comparable {
    public let name: String

    public init?(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        self.name = trimmed
    }

    public static func < (lhs: TaxonomicRank, rhs: TaxonomicRank) -> Bool {
        lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
}

/// A real Wikipedia article supplied by a source sitelink; URLs are never constructed from labels.
public struct WikipediaSitelink: Codable, Hashable, Sendable, Identifiable {
    public let language: TaxonLanguage
    public let title: String
    public let url: URL

    public var id: String { language.rawValue }

    public init?(language: TaxonLanguage, title: String, url: URL) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        self.language = language
        self.title = trimmed
        self.url = url
    }
}

/// A provider-neutral taxonomic entity. Its only source identifier is the canonical Wikidata Q-ID.
public struct Taxon: Codable, Hashable, Sendable, Identifiable {
    public let identity: TaxonIdentity
    public let rank: TaxonomicRank?
    public let names: [LocalizedTaxonName]
    public let wikipediaSitelinks: [WikipediaSitelink]

    public var id: WikidataID { identity.wikidataID }
    public var wikidataID: WikidataID { identity.wikidataID }
    public var scientificName: ScientificName { identity.scientificName }

    public init(
        identity: TaxonIdentity,
        rank: TaxonomicRank? = nil,
        names: [LocalizedTaxonName] = [],
        wikipediaSitelinks: [WikipediaSitelink] = []
    ) {
        self.identity = identity
        self.rank = rank
        self.names = names
        self.wikipediaSitelinks = wikipediaSitelinks
    }

    public func preferredName(for language: TaxonLanguage) -> LocalizedTaxonName? {
        let matchingNames = names.filter { $0.language == language }
        return matchingNames.first(where: \.isPreferred) ?? matchingNames.first
    }

    /// Selects an existing sitelink using preferred language, configured order, then a stable any-language fallback.
    public func wikipediaSitelink(
        preferredLanguage: TaxonLanguage?,
        configuredLanguages: [TaxonLanguage]
    ) -> WikipediaSitelink? {
        let languageOrder = deduplicatedLanguages(
            (preferredLanguage.map { [$0] } ?? []) + configuredLanguages
        )

        for language in languageOrder {
            if let exact = wikipediaSitelinks.first(where: { $0.language == language }) {
                return exact
            }
            if let baseMatch = wikipediaSitelinks.first(where: { $0.language.baseLanguageCode == language.baseLanguageCode }) {
                return baseMatch
            }
        }

        return wikipediaSitelinks.sorted { $0.language < $1.language }.first
    }
}

public enum ScientificNamePosition: String, Codable, Hashable, Sendable {
    case first
    case last
}

/// User-configured output ordering. Missing localized names remain explicit rows.
public struct OutputLanguageConfiguration: Codable, Hashable, Sendable {
    public let languages: [TaxonLanguage]
    public let scientificNamePosition: ScientificNamePosition

    public init(languages: [TaxonLanguage], scientificNamePosition: ScientificNamePosition = .last) {
        self.languages = deduplicatedLanguages(languages)
        self.scientificNamePosition = scientificNamePosition
    }

    public func displayRows(for taxon: Taxon) -> [TaxonDisplayRow] {
        let localizedRows = languages.map { language in
            TaxonDisplayRow.localized(language: language, name: taxon.preferredName(for: language))
        }
        let scientificRow = TaxonDisplayRow.scientific(taxon.scientificName)
        switch scientificNamePosition {
        case .first: return [scientificRow] + localizedRows
        case .last: return localizedRows + [scientificRow]
        }
    }
}

public enum TaxonDisplayRow: Hashable, Sendable, Identifiable {
    case localized(language: TaxonLanguage, name: LocalizedTaxonName?)
    case scientific(ScientificName)

    public var id: String {
        switch self {
        case let .localized(language, _): return "localized-\(language.rawValue)"
        case .scientific: return "scientific"
        }
    }
}

/// A non-empty user query with a deterministic comparison key.
public struct TaxonSearchQuery: Codable, Hashable, Sendable {
    public let originalText: String
    public let normalizedText: String

    public init?(_ text: String) {
        let original = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = Self.normalize(text)
        guard !normalized.isEmpty else { return nil }
        self.originalText = original
        self.normalizedText = normalized
    }

    public static func normalize(_ text: String) -> String {
        let collapsedWhitespace = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return collapsedWhitespace
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
    }
}

public enum TaxonMatchKind: Int, Codable, Hashable, Sendable, Comparable {
    case exactScientificName = 0
    case exactLocalizedName = 1
    case prefix = 2
    case upstreamSuggestion = 3

    public static func < (lhs: TaxonMatchKind, rhs: TaxonMatchKind) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Enough context for an explicit user choice when a query is ambiguous.
public struct TaxonCandidate: Hashable, Sendable, Identifiable {
    public let taxon: Taxon
    public let matchKind: TaxonMatchKind
    public let matchedName: String?

    public var id: WikidataID { taxon.id }

    public init(taxon: Taxon, matchKind: TaxonMatchKind, matchedName: String? = nil) {
        self.taxon = taxon
        self.matchKind = matchKind
        self.matchedName = matchedName
    }
}

public enum TaxonResolution: Hashable, Sendable {
    case resolved(Taxon)
    case candidates([TaxonCandidate])
    case noMatch
}

/// Failures distinct from an otherwise valid no-match or missing localized name.
public enum TaxonResolutionError: Error, Hashable, Sendable {
    case networkUnavailable
    case rateLimited(retryAfter: TimeInterval?)
    case temporaryServerFailure
    case invalidProviderResponse
}

/// Provider boundary used by the app, App Intents, cache, and fixture implementations.
public protocol TaxonResolving: Sendable {
    func resolve(query: TaxonSearchQuery, languages: [TaxonLanguage]) async throws -> TaxonResolution
    func taxon(for wikidataID: WikidataID, languages: [TaxonLanguage]) async throws -> Taxon?
}

private func deduplicatedLanguages(_ languages: [TaxonLanguage]) -> [TaxonLanguage] {
    var seen = Set<TaxonLanguage>()
    return languages.filter { seen.insert($0).inserted }
}
