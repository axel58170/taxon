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
        let gates = try await taxonGates(for: candidateIDs)
        guard !gates.isEmpty else { return .noMatch }
        let taxa = try await hydrate(ids: gates.map(\.id), languages: languages, gates: gates)
        return resolution(for: taxa, query: query)
    }

    public func taxon(for wikidataID: WikidataID, languages: [TaxonLanguage]) async throws -> Taxon? {
        let gates = try await taxonGates(for: [wikidataID])
        guard !gates.isEmpty else { return nil }
        return try await hydrate(ids: [wikidataID], languages: languages, gates: gates).first
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

    private func hydrate(ids: [WikidataID], languages: [TaxonLanguage], gates: [TaxonGate]) async throws -> [Taxon] {
        let languageCodes = orderedSearchLanguages(languages).map(\.baseLanguageCode).joined(separator: "|")
        let response: EntityResponse = try await request(
            actionURL(parameters: [
                "action": "wbgetentities",
                "ids": ids.map(\.rawValue).joined(separator: "|"),
                "languages": languageCodes,
                "props": "labels|aliases|claims|sitelinks",
                "format": "json"
            ])
        )
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
        struct Claim: Decodable { let mainsnak: Snak }
        struct Sitelink: Decodable { let site: String; let title: String; let url: URL? }

        let labels: [String: LanguageValue]?
        let aliases: [String: [LanguageValue]]?
        let claims: [String: [Claim]]?
        let sitelinks: [String: Sitelink]?

        var scientificName: String? { claimString(property: "P225") }
        var rankID: WikidataID? { claimEntityID(property: "P105") }

        func localizedNames(requestedLanguages: [TaxonLanguage]) -> [LocalizedTaxonName] {
            let languages = requestedLanguages.isEmpty ? [] : requestedLanguages
            return languages.compactMap { language in
                let code = language.baseLanguageCode
                if let label = labels?[code]?.value {
                    return LocalizedTaxonName(language: language, value: label, source: .wikidata, isPreferred: true)
                }
                if let alias = aliases?[code]?.first?.value {
                    return LocalizedTaxonName(language: language, value: alias, source: .wikidata, isPreferred: false)
                }
                return nil
            }
        }

        var wikipediaSitelinks: [WikipediaSitelink] {
            (sitelinks ?? [:]).values.compactMap { link in
                guard link.site.hasSuffix("wiki"), link.site != "commonswiki",
                      let language = TaxonLanguage(rawValue: String(link.site.dropLast(4))),
                      let url = link.url else { return nil }
                return WikipediaSitelink(language: language, title: link.title, url: url)
            }.sorted { $0.language < $1.language }
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
    }
}

private enum JSONValue: Decodable {
    case string(String)
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }
}
