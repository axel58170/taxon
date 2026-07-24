import Foundation
import TaxonDomain

/// Adds Catalogue of Life vernacular names to an already identified taxon.
///
/// Catalogue of Life records are accepted only when both the scientific name
/// and a Wikidata identifier agree with Taxon's canonical identity. This keeps
/// homonyms and similarly ranked search suggestions from enriching the wrong
/// taxon while provider-specific identifiers remain inside this module.
public struct CatalogueOfLifeProvider: Sendable {
    public struct ReleaseAttribution: Sendable, Equatable {
        public enum License: Sendable, Equatable {
            case creativeCommonsAttribution4
            case creativeCommonsZero1
            case unknown(String)
        }

        public let version: String
        public let doi: String
        public let license: License

        public init?(version: String, doi: String, license: License) {
            let version = version.trimmingCharacters(in: .whitespacesAndNewlines)
            let doi = doi.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !version.isEmpty, !doi.isEmpty else { return nil }
            self.version = version
            self.doi = doi
            self.license = license
        }

        public var doiURL: URL? {
            if let url = URL(string: doi), url.scheme != nil {
                return url
            }
            guard
                doi.hasPrefix("10."),
                !doi.contains(where: { $0.isWhitespace || $0.isNewline })
            else {
                return nil
            }
            return URL(string: "https://doi.org/\(doi)")
        }

        public var licenseURL: URL? {
            switch license {
            case .creativeCommonsAttribution4:
                return URL(string: "https://creativecommons.org/licenses/by/4.0/")
            case .creativeCommonsZero1:
                return URL(string: "https://creativecommons.org/publicdomain/zero/1.0/")
            case .unknown:
                return nil
            }
        }
    }

    public struct Configuration: Sendable {
        public var baseURL: URL
        public var datasetAlias: String
        public var userAgent: String
        public var candidateLimit: Int

        public init(
            baseURL: URL = URL(string: "https://api.checklistbank.org")!,
            datasetAlias: String = "3LXR",
            userAgent: String = "Taxon/0.1 (https://github.com/axel58170/taxon)",
            candidateLimit: Int = 20
        ) {
            self.baseURL = baseURL
            self.datasetAlias = datasetAlias
            self.userAgent = userAgent
            self.candidateLimit = min(max(candidateLimit, 1), 50)
        }
    }

    private let session: URLSession
    private let configuration: Configuration
    private let requests: NameRequestCoalescer

    public init(
        session: URLSession = .shared,
        configuration: Configuration = .init()
    ) {
        self.session = session
        self.configuration = configuration
        self.requests = NameRequestCoalescer()
    }

    /// Returns attribution metadata for the configured Catalogue of Life release.
    public func releaseAttribution() async throws -> ReleaseAttribution {
        let response: DatasetResponse = try await request(datasetURL())
        let license = response.license.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let attribution = ReleaseAttribution(
            version: response.version,
            doi: response.doi,
            license: releaseLicense(from: license)
        ), !license.isEmpty else {
            throw TaxonResolutionError.invalidProviderResponse
        }
        return attribution
    }

    /// Returns verified Catalogue of Life names in the caller's language order.
    public func names(
        for taxon: Taxon,
        languages: [TaxonLanguage]
    ) async throws -> [LocalizedTaxonName] {
        guard !languages.isEmpty else { return [] }

        let key = NameRequestKey(
            identity: taxon.identity,
            languages: languages
        )
        return try await requests.value(for: key) {
            try await loadNames(for: taxon, languages: languages)
        }
    }

    private func loadNames(
        for taxon: Taxon,
        languages: [TaxonLanguage]
    ) async throws -> [LocalizedTaxonName] {
        let response: SearchResponse = try await request(
            searchURL(scientificName: taxon.scientificName.value)
        )
        let matchingResults = (response.result ?? []).filter {
            $0.matches(identity: taxon.identity)
        }
        guard !matchingResults.isEmpty else { return [] }

        return mapNames(
            matchingResults.flatMap { $0.vernacularNames ?? [] },
            scientificName: taxon.scientificName,
            languages: languages
        )
    }

    /// Returns the original taxon with verified Catalogue of Life names appended.
    public func enrich(
        _ taxon: Taxon,
        languages: [TaxonLanguage]
    ) async throws -> Taxon {
        let catalogueNames = try await names(for: taxon, languages: languages)
        guard !catalogueNames.isEmpty else { return taxon }

        var seen = Set(
            taxon.names.map {
                NameKey(
                    language: $0.language,
                    value: TaxonSearchQuery.normalize($0.value),
                    regionCode: $0.regionCode?.uppercased()
                )
            }
        )
        let additions = catalogueNames.filter {
            seen.insert(
                NameKey(
                    language: $0.language,
                    value: TaxonSearchQuery.normalize($0.value),
                    regionCode: $0.regionCode?.uppercased()
                )
            ).inserted
        }

        return Taxon(
            identity: taxon.identity,
            rank: taxon.rank,
            names: taxon.names + additions,
            wikipediaSitelinks: taxon.wikipediaSitelinks
        )
    }

    fileprivate func discover(
        query: TaxonSearchQuery,
        languages: [TaxonLanguage]
    ) async throws -> [DiscoveredTaxon] {
        async let scientificResponse: SearchResponse = request(
            searchURL(scientificName: query.originalText)
        )
        async let vernacularResponse: VernacularSearchResponse = request(
            vernacularSearchURL(query: query.originalText)
        )
        let (scientific, vernacular) = try await (
            scientificResponse,
            vernacularResponse
        )

        var discoveries = (scientific.result ?? []).compactMap {
            $0.discovery(query: query, languages: languages, provider: self)
        }
        var seenTaxonIDs = Set(discoveries.map(\.catalogueOfLifeID))
        let vernacularMatches = (vernacular.result ?? []).filter {
            TaxonSearchQuery.normalize($0.name) == query.normalizedText
                && seenTaxonIDs.insert($0.taxonID).inserted
        }

        let hydrated = try await withThrowingTaskGroup(
            of: DiscoveredTaxon?.self,
            returning: [DiscoveredTaxon].self
        ) { group in
            for match in vernacularMatches.prefix(configuration.candidateLimit) {
                group.addTask {
                    try await hydrateDiscovery(
                        match: match,
                        languages: languages
                    )
                }
            }
            var values = [DiscoveredTaxon]()
            for try await value in group {
                if let value { values.append(value) }
            }
            return values
        }
        discoveries.append(contentsOf: hydrated)

        var seenIdentities = Set<TaxonIdentity>()
        return discoveries
            .filter { seenIdentities.insert($0.identity).inserted }
            .sorted {
                if $0.matchKind != $1.matchKind {
                    return $0.matchKind < $1.matchKind
                }
                return $0.identity.scientificName.value
                    .localizedCaseInsensitiveCompare(
                        $1.identity.scientificName.value
                    ) == .orderedAscending
            }
    }

    private func hydrateDiscovery(
        match: VernacularSearchResponse.Result,
        languages: [TaxonLanguage]
    ) async throws -> DiscoveredTaxon? {
        async let usage: TaxonResponse = request(
            taxonURL(id: match.taxonID)
        )
        async let records: [SearchResponse.VernacularName] = request(
            taxonVernacularURL(id: match.taxonID)
        )
        let (taxon, vernacularNames) = try await (usage, records)
        guard
            taxon.status.caseInsensitiveCompare("accepted") == .orderedSame,
            let scientificName = ScientificName(taxon.name.scientificName),
            let wikidataID = wikidataID(in: taxon.identifier)
        else {
            return nil
        }

        return DiscoveredTaxon(
            catalogueOfLifeID: match.taxonID,
            identity: TaxonIdentity(
                wikidataID: wikidataID,
                scientificName: scientificName
            ),
            rank: taxon.name.rank.flatMap(TaxonomicRank.init),
            names: mapNames(
                vernacularNames,
                scientificName: scientificName,
                languages: languages
            ),
            matchKind: .exactLocalizedName,
            matchedName: match.name
        )
    }

    private func mapNames(
        _ records: [SearchResponse.VernacularName],
        scientificName: ScientificName,
        languages: [TaxonLanguage]
    ) -> [LocalizedTaxonName] {
        let requestedLanguages = deduplicated(languages)
        let requestedByBaseCode = Dictionary(
            requestedLanguages.map { ($0.baseLanguageCode, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let normalizedScientificName = TaxonSearchQuery.normalize(scientificName.value)

        let mapped = records.compactMap { record -> MappedName? in
            guard
                let recordLanguage = record.language,
                let providerBaseCode = Locale.Language(identifier: recordLanguage)
                    .languageCode?.identifier.lowercased(),
                let language = requestedByBaseCode[providerBaseCode],
                let name = LocalizedTaxonName(
                    language: language,
                    value: record.name,
                    source: .catalogueOfLife,
                    regionCode: record.country,
                    isPreferred: record.preferred ?? false
                ),
                TaxonSearchQuery.normalize(name.value) != normalizedScientificName
            else {
                return nil
            }

            return MappedName(
                name: name,
                languageIndex: requestedLanguages.firstIndex(of: language) ?? .max,
                matchesRequestedRegion: requestedRegion(of: language) == record.country?.uppercased()
            )
        }.sorted {
            if $0.languageIndex != $1.languageIndex {
                return $0.languageIndex < $1.languageIndex
            }
            if $0.name.isPreferred != $1.name.isPreferred {
                return $0.name.isPreferred
            }
            if $0.matchesRequestedRegion != $1.matchesRequestedRegion {
                return $0.matchesRequestedRegion
            }
            if ($0.name.regionCode == nil) != ($1.name.regionCode == nil) {
                return $0.name.regionCode == nil
            }
            return $0.name.value.localizedCaseInsensitiveCompare($1.name.value) == .orderedAscending
        }

        var seen = Set<NameKey>()
        return mapped.compactMap { mappedName in
            let key = NameKey(
                language: mappedName.name.language,
                value: TaxonSearchQuery.normalize(mappedName.name.value),
                regionCode: mappedName.name.regionCode?.uppercased()
            )
            return seen.insert(key).inserted ? mappedName.name : nil
        }
    }

    private func searchURL(scientificName: String) -> URL {
        var url = configuration.baseURL
        for component in [
            "dataset",
            configuration.datasetAlias,
            "nameusage",
            "search"
        ] {
            url.append(path: component)
        }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: scientificName),
            URLQueryItem(name: "status", value: "accepted"),
            URLQueryItem(name: "limit", value: String(configuration.candidateLimit))
        ]
        return components.url!
    }

    private func datasetURL() -> URL {
        var url = configuration.baseURL
        url.append(path: "dataset")
        url.append(path: configuration.datasetAlias)
        return url
    }

    private func vernacularSearchURL(query: String) -> URL {
        var url = configuration.baseURL
        for component in ["dataset", configuration.datasetAlias, "vernacular"] {
            url.append(path: component)
        }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(configuration.candidateLimit))
        ]
        return components.url!
    }

    private func taxonURL(id: String) -> URL {
        var url = configuration.baseURL
        for component in ["dataset", configuration.datasetAlias, "taxon", id] {
            url.append(path: component)
        }
        return url
    }

    private func taxonVernacularURL(id: String) -> URL {
        taxonURL(id: id).appending(path: "vernacular")
    }

    private func wikidataID(in identifiers: [String]?) -> WikidataID? {
        identifiers?.lazy.compactMap { identifier in
            guard identifier.lowercased().hasPrefix("wikidata:") else {
                return nil
            }
            return WikidataID(rawValue: String(identifier.dropFirst(9)))
        }.first
    }

    private func releaseLicense(from value: String) -> ReleaseAttribution.License {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        if [
            "cc by",
            "cc by 4.0",
            "creative commons attribution 4.0"
        ].contains(normalized) {
            return .creativeCommonsAttribution4
        }
        if [
            "cc0",
            "cc0 1.0",
            "cc zero",
            "cc zero 1.0"
        ].contains(normalized) {
            return .creativeCommonsZero1
        }
        return .unknown(trimmed)
    }

    private func request<Response: Decodable>(_ url: URL) async throws -> Response {
        var request = URLRequest(url: url)
        request.setValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw TaxonResolutionError.networkUnavailable
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TaxonResolutionError.networkUnavailable
        }
        switch httpResponse.statusCode {
        case 200..<300:
            break
        case 429:
            throw TaxonResolutionError.rateLimited(
                retryAfter: retryAfter(from: httpResponse)
            )
        case 500...599:
            throw TaxonResolutionError.temporaryServerFailure
        default:
            throw TaxonResolutionError.invalidProviderResponse
        }

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw TaxonResolutionError.invalidProviderResponse
        }
    }

    private func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else {
            return nil
        }
        return TimeInterval(value)
    }
}

/// Uses Catalogue of Life for scientific and vernacular discovery, then asks
/// Wikidata to verify canonical identity and hydrate sitelinks.
///
/// The secondary resolver's text search is used only when Catalogue of Life has
/// no verified match or is unavailable. Ambiguous COL names remain candidates.
public struct CatalogueOfLifePrimaryResolver<Secondary: TaxonResolving>: TaxonResolving, Sendable {
    private let secondary: Secondary
    private let catalogueOfLife: CatalogueOfLifeProvider

    public init(
        secondary: Secondary,
        catalogueOfLife: CatalogueOfLifeProvider = .init()
    ) {
        self.secondary = secondary
        self.catalogueOfLife = catalogueOfLife
    }

    public func resolve(
        query: TaxonSearchQuery,
        languages: [TaxonLanguage]
    ) async throws -> TaxonResolution {
        do {
            let discoveries = try await catalogueOfLife.discover(
                query: query,
                languages: languages
            )
            let candidates = try await verifiedCandidates(
                discoveries,
                languages: languages
            )
            switch candidates.count {
            case 1:
                return .resolved(candidates[0].taxon)
            case 2...:
                return .candidates(candidates)
            default:
                break
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Continue with secondary text discovery when COL is unavailable.
        }
        return try await secondary.resolve(query: query, languages: languages)
    }

    public func taxon(
        for wikidataID: WikidataID,
        languages: [TaxonLanguage]
    ) async throws -> Taxon? {
        guard let taxon = try await secondary.taxon(
            for: wikidataID,
            languages: languages
        ) else {
            return nil
        }
        return try await bestEffortEnrichment(of: taxon, languages: languages)
    }

    private func bestEffortEnrichment(
        of taxon: Taxon,
        languages: [TaxonLanguage]
    ) async throws -> Taxon {
        do {
            return try await catalogueOfLife.enrich(taxon, languages: languages)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return taxon
        }
    }

    private func verifiedCandidates(
        _ discoveries: [DiscoveredTaxon],
        languages: [TaxonLanguage]
    ) async throws -> [TaxonCandidate] {
        var candidates = [TaxonCandidate]()
        for discovery in discoveries {
            guard
                let wikidataTaxon = try await secondary.taxon(
                    for: discovery.identity.wikidataID,
                    languages: languages
                ),
                TaxonSearchQuery.normalize(
                    wikidataTaxon.scientificName.value
                ) == TaxonSearchQuery.normalize(
                    discovery.identity.scientificName.value
                )
            else {
                continue
            }

            let enriched = merge(
                discovery: discovery,
                into: wikidataTaxon
            )
            candidates.append(
                TaxonCandidate(
                    taxon: enriched,
                    matchKind: discovery.matchKind,
                    matchedName: discovery.matchedName
                )
            )
        }
        return candidates
    }

    private func merge(
        discovery: DiscoveredTaxon,
        into taxon: Taxon
    ) -> Taxon {
        var seen = Set(
            taxon.names.map {
                NameMergeKey(
                    language: $0.language,
                    value: TaxonSearchQuery.normalize($0.value),
                    regionCode: $0.regionCode?.uppercased()
                )
            }
        )
        let additions = discovery.names.filter {
            seen.insert(
                NameMergeKey(
                    language: $0.language,
                    value: TaxonSearchQuery.normalize($0.value),
                    regionCode: $0.regionCode?.uppercased()
                )
            ).inserted
        }
        return Taxon(
            identity: taxon.identity,
            rank: taxon.rank ?? discovery.rank,
            names: taxon.names + additions,
            wikipediaSitelinks: taxon.wikipediaSitelinks
        )
    }
}

@available(*, deprecated, renamed: "CatalogueOfLifePrimaryResolver")
public typealias CatalogueOfLifeEnrichingResolver<Base: TaxonResolving>
    = CatalogueOfLifePrimaryResolver<Base>

private struct NameRequestKey: Hashable, Sendable {
    let identity: TaxonIdentity
    let languages: [TaxonLanguage]
}

private struct NameMergeKey: Hashable {
    let language: TaxonLanguage
    let value: String
    let regionCode: String?
}

private struct DiscoveredTaxon: Sendable {
    let catalogueOfLifeID: String
    let identity: TaxonIdentity
    let rank: TaxonomicRank?
    let names: [LocalizedTaxonName]
    let matchKind: TaxonMatchKind
    let matchedName: String
}

private actor NameRequestCoalescer {
    private struct Entry {
        let id: UUID
        let task: Task<[LocalizedTaxonName], Error>
    }

    private var entries = [NameRequestKey: Entry]()

    func value(
        for key: NameRequestKey,
        operation: @escaping @Sendable () async throws -> [LocalizedTaxonName]
    ) async throws -> [LocalizedTaxonName] {
        if let entry = entries[key] {
            let value = try await entry.task.value
            try Task.checkCancellation()
            return value
        }

        let id = UUID()
        let task = Task { try await operation() }
        entries[key] = Entry(id: id, task: task)
        do {
            let value = try await task.value
            removeEntry(for: key, id: id)
            try Task.checkCancellation()
            return value
        } catch {
            removeEntry(for: key, id: id)
            throw error
        }
    }

    private func removeEntry(for key: NameRequestKey, id: UUID) {
        guard entries[key]?.id == id else { return }
        entries.removeValue(forKey: key)
    }
}

private extension CatalogueOfLifeProvider {
    struct DatasetResponse: Decodable {
        let version: String
        let doi: String
        let license: String
    }

    struct SearchResponse: Decodable {
        struct Result: Decodable {
            struct Usage: Decodable {
                struct Name: Decodable {
                    let scientificName: String
                    let rank: String?
                }

                let id: String
                let status: String
                let name: Name
                let identifier: [String]?
            }

            let usage: Usage
            let vernacularNames: [VernacularName]?

            func matches(identity: TaxonIdentity) -> Bool {
                guard
                    usage.status.caseInsensitiveCompare("accepted") == .orderedSame,
                    TaxonSearchQuery.normalize(usage.name.scientificName)
                        == TaxonSearchQuery.normalize(identity.scientificName.value)
                else {
                    return false
                }
                let expectedIdentifier = "wikidata:\(identity.wikidataID.rawValue)"
                return usage.identifier?.contains {
                    $0.caseInsensitiveCompare(expectedIdentifier) == .orderedSame
                } == true
            }

            func discovery(
                query: TaxonSearchQuery,
                languages: [TaxonLanguage],
                provider: CatalogueOfLifeProvider
            ) -> DiscoveredTaxon? {
                guard
                    usage.status.caseInsensitiveCompare("accepted") == .orderedSame,
                    TaxonSearchQuery.normalize(usage.name.scientificName)
                        == query.normalizedText,
                    let scientificName = ScientificName(
                        usage.name.scientificName
                    ),
                    let wikidataID = provider.wikidataID(
                        in: usage.identifier
                    )
                else {
                    return nil
                }

                return DiscoveredTaxon(
                    catalogueOfLifeID: usage.id,
                    identity: TaxonIdentity(
                        wikidataID: wikidataID,
                        scientificName: scientificName
                    ),
                    rank: usage.name.rank.flatMap(TaxonomicRank.init),
                    names: provider.mapNames(
                        vernacularNames ?? [],
                        scientificName: scientificName,
                        languages: languages
                    ),
                    matchKind: .exactScientificName,
                    matchedName: usage.name.scientificName
                )
            }
        }

        struct VernacularName: Decodable {
            let name: String
            let language: String?
            let preferred: Bool?
            let country: String?
            let area: String?
        }

        let result: [Result]?
    }

    struct VernacularSearchResponse: Decodable {
        struct Result: Decodable {
            let taxonID: String
            let name: String
            let language: String?
            let preferred: Bool?
            let country: String?
            let area: String?
        }

        let result: [Result]?
    }

    struct TaxonResponse: Decodable {
        struct Name: Decodable {
            let scientificName: String
            let rank: String?
        }

        let id: String
        let status: String
        let name: Name
        let identifier: [String]?
    }

    struct NameKey: Hashable {
        let language: TaxonLanguage
        let value: String
        let regionCode: String?
    }

    struct MappedName {
        let name: LocalizedTaxonName
        let languageIndex: Int
        let matchesRequestedRegion: Bool
    }

    func deduplicated(_ languages: [TaxonLanguage]) -> [TaxonLanguage] {
        var seen = Set<TaxonLanguage>()
        return languages.filter { seen.insert($0).inserted }
    }

    func requestedRegion(of language: TaxonLanguage) -> String? {
        let pieces = language.rawValue.split(separator: "-")
        return pieces.dropFirst().first.flatMap { piece in
            let value = String(piece)
            return value.count == 2 ? value.uppercased() : nil
        }
    }
}
