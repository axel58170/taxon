import Foundation
import Testing
@testable import WikidataProvider
import TaxonDomain

@MainActor
struct WikidataProviderTests {
    private let english = TaxonLanguage(rawValue: "en")!
    private let dutch = TaxonLanguage(rawValue: "nl")!
    private let french = TaxonLanguage(rawValue: "fr")!
    private let italian = TaxonLanguage(rawValue: "it")!

    @Test("Wespendief resolves through search, taxon gate, and entity hydration")
    func resolvesWespendief() async throws {
        let transport = FixtureTransport(search: "search-wespendief", gate: "gate-honey-buzzard", entities: "entities-honey-buzzard")
        let resolution = try await provider(transport).resolve(query: #require(TaxonSearchQuery("wespendief")), languages: [dutch, english, french])

        guard case let .resolved(taxon) = resolution else { Issue.record("Expected a resolved taxon"); return }
        #expect(taxon.wikidataID.rawValue == "Q170466")
        #expect(taxon.scientificName.value == "Pernis apivorus")
        #expect(taxon.rank?.name == "species") // P105 fixture includes Wikidata's numeric-id field.
        #expect(taxon.preferredName(for: dutch)?.value == "Wespendief")
        #expect(taxon.wikipediaSitelinks.map(\.language) == [french, dutch])
        #expect(taxon.wikipediaSitelinks.map(\.url.absoluteString) == [
            "https://fr.wikipedia.org/wiki/Bondr%C3%A9e%20apivore",
            "https://nl.wikipedia.org/wiki/Wespendief"
        ])
        #expect(transport.userAgents.allSatisfy { $0 == "TaxonTests/1.0 (fixture)" })
    }

    @Test("Scientific names receive the strongest candidate rank")
    func ranksScientificName() async throws {
        let resolution = try await provider(FixtureTransport(search: "search-scientific", gate: "gate-honey-buzzard", entities: "entities-honey-buzzard"))
            .resolve(query: #require(TaxonSearchQuery("Pernis apivorus")), languages: [english])

        guard case let .resolved(taxon) = resolution else { Issue.record("Expected a resolved taxon"); return }
        #expect(taxon.scientificName.value == "Pernis apivorus")
    }

    @Test("Accent-insensitive input ranks a localized Wikidata label")
    func ranksAccentedLocalizedName() async throws {
        let resolution = try await provider(FixtureTransport(search: "search-accented", gate: "gate-honey-buzzard", entities: "entities-honey-buzzard"))
            .resolve(query: #require(TaxonSearchQuery("BONDRÉE APIVORE")), languages: [french])

        guard case let .resolved(taxon) = resolution else { Issue.record("Expected a resolved taxon"); return }
        #expect(taxon.preferredName(for: french)?.value == "Bondrée apivore")
    }

    @Test("Plausible equal matches remain explicit candidates")
    func returnsAmbiguousCandidates() async throws {
        let resolution = try await provider(FixtureTransport(search: "search-ambiguous", gate: "gate-ambiguous", entities: "entities-ambiguous"))
            .resolve(query: #require(TaxonSearchQuery("Common Swift")), languages: [english])

        guard case let .candidates(candidates) = resolution else { Issue.record("Expected candidates"); return }
        #expect(candidates.map(\.taxon.wikidataID.rawValue) == ["Q100", "Q200"])
        #expect(candidates.allSatisfy { $0.matchKind == .exactLocalizedName })
    }

    @Test("Configured languages missing from Wikidata remain absent rather than fabricated")
    func preservesMissingLanguage() async throws {
        let resolution = try await provider(FixtureTransport(search: "search-wespendief", gate: "gate-honey-buzzard", entities: "entities-honey-buzzard"))
            .resolve(query: #require(TaxonSearchQuery("wespendief")), languages: [dutch, TaxonLanguage(rawValue: "de")!])

        guard case let .resolved(taxon) = resolution else { Issue.record("Expected a resolved taxon"); return }
        #expect(taxon.preferredName(for: TaxonLanguage(rawValue: "de")!) == nil)
    }

    @Test("A scientific Italian label does not hide the Common swift vernacular alias")
    func rejectsScientificEquivalentLabel() async throws {
        let taxon = try #require(await commonSwift(languages: [italian]))

        #expect(taxon.scientificName.value == "Apus apus")
        #expect(taxon.preferredName(for: italian)?.value == "Rondone")
    }

    @Test("A regional Italian request falls back to the base-language vernacular name")
    func fallsBackFromRegionalItalian() async throws {
        let regionalItalian = try #require(TaxonLanguage(rawValue: "it-IT"))
        let taxon = try #require(await commonSwift(languages: [regionalItalian]))

        #expect(taxon.preferredName(for: regionalItalian)?.value == "Rondone")
    }

    @Test("P1843 supplies a common name when labels and aliases are only scientific")
    func fallsBackToTaxonCommonNameClaim() async throws {
        let taxon = try #require(await commonSwift(languages: [english]))

        #expect(taxon.preferredName(for: english)?.value == "Common swift")
    }

    @Test("A non-taxon search result is rejected by the SPARQL gate")
    func rejectsNonTaxon() async throws {
        let resolution = try await provider(FixtureTransport(search: "search-non-taxon", gate: "gate-empty", entities: "entities-honey-buzzard"))
            .resolve(query: #require(TaxonSearchQuery("not a taxon")), languages: [english])
        #expect(resolution == .noMatch)
    }

    @Test("Rate limiting preserves Retry-After")
    func mapsRateLimit() async throws {
        let transport = FixtureTransport(search: "search-wespendief", gate: "gate-honey-buzzard", entities: "entities-honey-buzzard", statusCode: 429, retryAfter: "12")
        await #expect(throws: TaxonResolutionError.rateLimited(retryAfter: 12)) {
            try await provider(transport).resolve(query: #require(TaxonSearchQuery("wespendief")), languages: [english])
        }
    }

    private func provider(_ transport: FixtureTransport) -> WikidataProvider {
        WikidataProvider(
            session: transport.session,
            configuration: .init(
                actionAPIBaseURL: transport.actionAPIBaseURL,
                queryServiceURL: transport.queryServiceURL,
                userAgent: "TaxonTests/1.0 (fixture)"
            )
        )
    }

    private func commonSwift(languages: [TaxonLanguage]) async throws -> Taxon? {
        try await provider(
            FixtureTransport(
                search: "search-scientific",
                gate: "gate-common-swift",
                entities: "entities-common-swift"
            )
        ).taxon(for: WikidataID(rawValue: "Q25377")!, languages: languages)
    }
}

private final class FixtureTransport: @unchecked Sendable {
    let session: URLSession
    let actionAPIBaseURL: URL
    let queryServiceURL: URL
    private let fixtures: [String: Data]
    private let statusCode: Int
    private let retryAfter: String?
    private let lock = NSLock()
    private(set) var userAgents: [String] = []

    init(search: String, gate: String, entities: String, statusCode: Int = 200, retryAfter: String? = nil) {
        let identifier = UUID().uuidString.lowercased()
        self.actionAPIBaseURL = URL(string: "https://action-\(identifier).fixture/w/api.php")!
        self.queryServiceURL = URL(string: "https://query-\(identifier).fixture/sparql")!
        self.fixtures = ["search": fixture(search), "gate": fixture(gate), "entities": fixture(entities)]
        self.statusCode = statusCode
        self.retryAfter = retryAfter
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureURLProtocol.self]
        self.session = URLSession(configuration: configuration)
        FixtureURLProtocol.install(transport: self)
    }

    fileprivate func response(for request: URLRequest) -> (HTTPURLResponse, Data) {
        lock.lock()
        userAgents.append(request.value(forHTTPHeaderField: "User-Agent") ?? "")
        lock.unlock()
        let key = request.url?.host == queryServiceURL.host ? "gate" : request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "action" })?.value } == "wbgetentities" ? "entities" : "search"
        var headers = [String: String]()
        if let retryAfter { headers["Retry-After"] = retryAfter }
        let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: headers)!
        return (response, fixtures[key]!)
    }
}

private final class FixtureURLProtocol: URLProtocol {
    private static let registry = FixtureTransportRegistry()

    static func install(transport: FixtureTransport) {
        registry.insert(transport)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let activeTransport = request.url?.host.flatMap(Self.registry.transport(forHost:))
        guard let activeTransport else { return }
        let (response, data) = activeTransport.response(for: request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class FixtureTransportRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var transports: [String: FixtureTransport] = [:]

    func insert(_ transport: FixtureTransport) {
        lock.lock()
        transports[transport.actionAPIBaseURL.host!] = transport
        transports[transport.queryServiceURL.host!] = transport
        lock.unlock()
    }

    func transport(forHost host: String) -> FixtureTransport? {
        lock.lock()
        defer { lock.unlock() }
        return transports[host]
    }
}

private func fixture(_ name: String) -> Data {
    let url = Bundle.module.url(forResource: name, withExtension: "json")!
    return try! Data(contentsOf: url)
}
