import Foundation
import TaxonDomain

/// Wikidata-backed implementation of Taxon's provider boundary.
///
/// Text discovery uses the MediaWiki Action API. A bounded SPARQL `VALUES` query
/// rejects non-taxa before a single Action API hydration request maps domain values.
public struct WikidataProvider: TaxonResolving, Sendable {
    public struct Configuration: Sendable {
        public var actionAPIBaseURL: URL
        public var queryServiceURL: URL
        public var userAgent: String
        public var candidateLimit: Int

        public init(
            actionAPIBaseURL: URL = URL(string: "https://www.wikidata.org/w/api.php")!,
            queryServiceURL: URL = URL(string: "https://query.wikidata.org/sparql")!,
            userAgent: String = "Taxon/0.1 (https://github.com/axel58170/taxon)",
            candidateLimit: Int = 20
        ) {
            self.actionAPIBaseURL = actionAPIBaseURL
            self.queryServiceURL = queryServiceURL
            self.userAgent = userAgent
            self.candidateLimit = min(max(candidateLimit, 1), 50)
        }
    }

    private let session: URLSession
    private let configuration: Configuration

    public init(session: URLSession = .shared, configuration: Configuration = .init()) {
        self.session = session
        self.configuration = configuration
    }

    public func resolve(query: TaxonSearchQuery, languages: [TaxonLanguage]) async throws -> TaxonResolution {
        let searchLanguages = orderedSearchLanguages(languages)
        var candidateIDs: [WikidataID] = []
        var seen = Set<WikidataID>()

        search: for language in searchLanguages {
            let response: SearchResponse = try await request(
                actionURL(parameters: [
                    "action": "wbsearchentities",
                    "search": query.originalText,
                    "language": language.baseLanguageCode,
                    "type": "item",
                    "limit": String(configuration.candidateLimit),
                    "format": "json"
                ])
            )
            for result in response.search {
                guard let id = WikidataID(rawValue: result.id), seen.insert(id).inserted else { continue }
                candidateIDs.append(id)
                if candidateIDs.count == configuration.candidateLimit {
                    break search
                }
            }
        }

        guard !candidateIDs.isEmpty else { return .noMatch }
        let taxa = try await validatedTaxa(
            ids: candidateIDs,
            languages: languages
        )
        return resolution(for: taxa, query: query)
    }

    public func taxon(for wikidataID: WikidataID, languages: [TaxonLanguage]) async throws -> Taxon? {
        try await validatedTaxa(ids: [wikidataID], languages: languages).first
    }

    private func resolution(for taxa: [Taxon], query: TaxonSearchQuery) -> TaxonResolution {
        let candidates = taxa.map { taxon in
            let match = match(for: taxon, query: query)
            return TaxonCandidate(taxon: taxon, matchKind: match.kind, matchedName: match.value)
        }.sorted {
            if $0.matchKind != $1.matchKind { return $0.matchKind < $1.matchKind }
            return $0.taxon.scientificName.value.localizedCaseInsensitiveCompare($1.taxon.scientificName.value) == .orderedAscending
        }

        switch candidates.count {
        case 0: return .noMatch
        case 1: return .resolved(candidates[0].taxon)
        default: return .candidates(candidates)
        }
    }

    private func match(for taxon: Taxon, query: TaxonSearchQuery) -> (kind: TaxonMatchKind, value: String?) {
        let scientific = taxon.scientificName.value
        if TaxonSearchQuery.normalize(scientific) == query.normalizedText {
            return (.exactScientificName, scientific)
        }

        let names = taxon.names
        if let exact = names.first(where: { TaxonSearchQuery.normalize($0.value) == query.normalizedText }) {
            return (.exactLocalizedName, exact.value)
        }
        if let prefix = ([scientific] + names.map(\.value)).first(where: {
            TaxonSearchQuery.normalize($0).hasPrefix(query.normalizedText)
        }) {
            return (.prefix, prefix)
        }
        return (.upstreamSuggestion, nil)
    }

    private func taxonGates(for ids: [WikidataID]) async throws -> [TaxonGate] {
        let values = ids.map { "wd:\($0.rawValue)" }.joined(separator: " ")
        let query = """
        SELECT ?item ?rank ?rankLabel WHERE {
          VALUES ?item { \(values) }
          ?item wdt:P31/wdt:P279* wd:Q16521 .
          OPTIONAL { ?item wdt:P105 ?rank . }
          SERVICE wikibase:label { bd:serviceParam wikibase:language \"en\". }
        }
        """
        let response: SPARQLResponse = try await request(queryServiceURL(query: query))
        var gatesByID: [WikidataID: TaxonGate] = [:]
        for binding in response.results.bindings {
            guard let id = binding.item.wikidataID else { continue }
            let rankID = binding.rank?.wikidataID
            let rankName = binding.rankLabel.flatMap { TaxonomicRank($0.value) }
            gatesByID[id] = TaxonGate(id: id, rankID: rankID, rank: rankName)
        }
        return ids.compactMap { gatesByID[$0] }
    }

    private func validatedTaxa(
        ids: [WikidataID],
        languages: [TaxonLanguage]
    ) async throws -> [Taxon] {
        async let pendingGates = taxonGates(for: ids)
        async let pendingEntities = entities(for: ids, languages: languages)
        let (gates, response) = try await (pendingGates, pendingEntities)
        guard !gates.isEmpty else { return [] }

        return mapEntities(response, ids: ids, languages: languages, gates: gates)
    }

    private func entities(
        for ids: [WikidataID],
        languages: [TaxonLanguage]
    ) async throws -> EntityResponse {
        let languageCodes = orderedSearchLanguages(languages).map(\.baseLanguageCode).joined(separator: "|")
        return try await request(
            actionURL(parameters: [
                "action": "wbgetentities",
                "ids": ids.map(\.rawValue).joined(separator: "|"),
                "languages": languageCodes,
                "props": "labels|aliases|claims|sitelinks",
                "format": "json"
            ])
        )
    }

    private func mapEntities(
        _ response: EntityResponse,
        ids: [WikidataID],
        languages: [TaxonLanguage],
        gates: [TaxonGate]
    ) -> [Taxon] {
        let gatesByID = Dictionary(uniqueKeysWithValues: gates.map { ($0.id, $0) })
        return ids.compactMap { id in
            guard let entity = response.entities[id.rawValue], let gate = gatesByID[id],
                  let scientificName = entity.scientificName.flatMap(ScientificName.init) else { return nil }
            let names = entity.localizedNames(requestedLanguages: languages)
            let rank = entity.rankID == gate.rankID ? gate.rank : gate.rank ?? entity.rankID.flatMap { TaxonomicRank($0.rawValue) }
            return Taxon(
                identity: TaxonIdentity(wikidataID: id, scientificName: scientificName),
                rank: rank,
                names: names,
                wikipediaSitelinks: entity.wikipediaSitelinks
            )
        }
    }

    private func orderedSearchLanguages(_ languages: [TaxonLanguage]) -> [TaxonLanguage] {
        var seen = Set<String>()
        let ordered = languages.filter { seen.insert($0.baseLanguageCode).inserted }
        return ordered.isEmpty ? [TaxonLanguage(rawValue: "en")!] : ordered
    }

    private func actionURL(parameters: [String: String]) -> URL {
        var components = URLComponents(url: configuration.actionAPIBaseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = parameters.sorted { $0.key < $1.key }.map {
            URLQueryItem(name: $0.key, value: $0.value)
        }
        return components.url!
    }

    private func queryServiceURL(query: String) -> URL {
        var components = URLComponents(url: configuration.queryServiceURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "query", value: query), URLQueryItem(name: "format", value: "json")]
        return components.url!
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
        guard let httpResponse = response as? HTTPURLResponse else { throw TaxonResolutionError.networkUnavailable }
        switch httpResponse.statusCode {
        case 200..<300: break
        case 429:
            throw TaxonResolutionError.rateLimited(retryAfter: retryAfter(from: httpResponse))
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
        guard let rawValue = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        return TimeInterval(rawValue)
    }
}

private struct TaxonGate: Sendable {
    let id: WikidataID
    let rankID: WikidataID?
    let rank: TaxonomicRank?
}

private struct SearchResponse: Decodable {
    struct Result: Decodable { let id: String }
    let search: [Result]
}

private struct SPARQLResponse: Decodable {
    struct Value: Decodable {
        let value: String
        var wikidataID: WikidataID? { WikidataID(rawValue: value.components(separatedBy: "/").last ?? value) }
    }
    struct Binding: Decodable { let item: Value; let rank: Value?; let rankLabel: Value? }
    struct Results: Decodable { let bindings: [Binding] }
    let results: Results
}

private struct EntityResponse: Decodable {
    let entities: [String: Entity]

    struct Entity: Decodable {
        struct LanguageValue: Decodable { let language: String; let value: String }
        struct Snak: Decodable {
            struct DataValue: Decodable { let value: JSONValue }
            let datavalue: DataValue?
        }
        struct Claim: Decodable {
            let mainsnak: Snak
            let rank: String?
        }
        struct Sitelink: Decodable { let site: String; let title: String; let url: URL? }

        let labels: [String: LanguageValue]?
        let aliases: [String: [LanguageValue]]?
        let claims: [String: [Claim]]?
        let sitelinks: [String: Sitelink]?

        var scientificName: String? { claimString(property: "P225") }
        var rankID: WikidataID? { claimEntityID(property: "P105") }

        func localizedNames(requestedLanguages: [TaxonLanguage]) -> [LocalizedTaxonName] {
            let languages = requestedLanguages.isEmpty ? [] : requestedLanguages
            return languages.flatMap { language -> [LocalizedTaxonName] in
                let code = language.baseLanguageCode
                let commonNameClaims = commonNames(languageCode: code)
                let preferredClaims = commonNameClaims
                    .filter { $0.rank == "preferred" }
                    .map(\.value)
                let normalClaims = commonNameClaims
                    .filter { $0.rank != "preferred" }
                    .map(\.value)
                let label = labels?[code]?.value
                let aliases = aliases?[code]?.map(\.value) ?? []

                let orderedCandidates = preferredClaims
                    + normalClaims
                    + (label.map { [$0] } ?? [])
                    + aliases

                var seen = Set<String>()
                let usableCandidates = orderedCandidates.filter { candidate in
                    let normalized = TaxonSearchQuery.normalize(candidate)
                    guard !normalized.isEmpty else { return false }
                    if let scientificName,
                       normalized == TaxonSearchQuery.normalize(scientificName) {
                        return false
                    }
                    return seen.insert(normalized).inserted
                }

                return usableCandidates.enumerated().compactMap { index, value in
                    LocalizedTaxonName(
                        language: language,
                        value: value,
                        source: .wikidata,
                        isPreferred: index == 0
                    )
                }
            }
        }

        var wikipediaSitelinks: [WikipediaSitelink] {
            (sitelinks ?? [:]).values.compactMap { link in
                guard let language = wikipediaLanguage(for: link.site),
                      let url = link.url ?? wikipediaURL(site: link.site, title: link.title) else { return nil }
                return WikipediaSitelink(language: language, title: link.title, url: url)
            }.sorted { $0.language < $1.language }
        }

        private func wikipediaLanguage(for site: String) -> TaxonLanguage? {
            let nonWikipediaSites: Set<String> = [
                "commonswiki", "mediawikiwiki", "metawiki", "outreachwiki", "specieswiki", "wikidatawiki"
            ]
            guard site.hasSuffix("wiki"), !nonWikipediaSites.contains(site) else { return nil }
            return TaxonLanguage(rawValue: String(site.dropLast(4)))
        }

        private func wikipediaURL(site: String, title: String) -> URL? {
            let languageCode = String(site.dropLast(4)).replacingOccurrences(of: "_", with: "-")
            let titleCharacters = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#%"))
            guard let encodedTitle = title.addingPercentEncoding(withAllowedCharacters: titleCharacters) else { return nil }
            var components = URLComponents()
            components.scheme = "https"
            components.host = "\(languageCode).wikipedia.org"
            components.percentEncodedPath = "/wiki/\(encodedTitle)"
            return components.url
        }

        private func claimString(property: String) -> String? {
            guard let propertyClaims = claims?[property] else { return nil }
            for claim in propertyClaims {
                if case let .string(value) = claim.mainsnak.datavalue?.value {
                    return value
                }
            }
            return nil
        }

        private func claimEntityID(property: String) -> WikidataID? {
            guard let propertyClaims = claims?[property] else { return nil }
            for claim in propertyClaims {
                guard case let .object(value) = claim.mainsnak.datavalue?.value,
                      case let .string(id)? = value["id"] else { continue }
                if let identifier = WikidataID(rawValue: id) { return identifier }
            }
            return nil
        }

        private func commonNames(languageCode: String) -> [(value: String, rank: String)] {
            (claims?["P1843"] ?? []).compactMap { claim in
                guard claim.rank != "deprecated",
                      case let .object(value) = claim.mainsnak.datavalue?.value,
                      case let .string(text)? = value["text"],
                      case let .string(language)? = value["language"],
                      TaxonLanguage(rawValue: language)?.baseLanguageCode == languageCode
                else {
                    return nil
                }
                return (text, claim.rank ?? "normal")
            }
        }
    }
}

private enum JSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }
}
