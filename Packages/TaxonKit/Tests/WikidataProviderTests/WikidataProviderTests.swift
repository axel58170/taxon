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

    @Test("P1843 takes precedence over a Common swift vernacular alias")
    func rejectsScientificEquivalentLabel() async throws {
        let taxon = try #require(await commonSwift(languages: [italian]))

        #expect(taxon.scientificName.value == "Apus apus")
        #expect(taxon.preferredName(for: italian)?.value == "Rondone comune")
    }

    @Test("A regional Italian request falls back to the base-language vernacular name")
    func fallsBackFromRegionalItalian() async throws {
        let regionalItalian = try #require(TaxonLanguage(rawValue: "it-IT"))
        let taxon = try #require(await commonSwift(languages: [regionalItalian]))

        #expect(taxon.preferredName(for: regionalItalian)?.value == "Rondone comune")
    }

    @Test("P1843 supplies a common name when labels and aliases are only scientific")
    func fallsBackToTaxonCommonNameClaim() async throws {
        let taxon = try #require(await commonSwift(languages: [english]))

        #expect(taxon.preferredName(for: english)?.value == "Common swift")
    }

    @Test("European Bee-eater prefers P1843 common names in every requested language")
    func prefersEuropeanBeeEaterCommonNameClaims() async throws {
        let taxon = try #require(await europeanBeeEater(languages: [english, french, dutch, italian]))

        #expect(taxon.wikidataID.rawValue == "Q170718")
        #expect(taxon.scientificName.value == "Merops apiaster")
        #expect(taxon.preferredName(for: english)?.value == "European Bee-eater")
        #expect(taxon.preferredName(for: french)?.value == "Guêpier d'Europe")
        #expect(taxon.preferredName(for: dutch)?.value == "Bijeneter")
        #expect(taxon.preferredName(for: italian)?.value == "Gruccione")
    }

    @Test("Deprecated P1843 values are excluded")
    func excludesDeprecatedCommonNameClaims() async throws {
        let taxon = try #require(await europeanBeeEater(languages: [italian]))

        #expect(taxon.names.contains(where: { $0.value == "Deprecated gruccione" }) == false)
        #expect(taxon.preferredName(for: italian)?.value == "Gruccione")
    }

    @Test("A non-taxon search result is rejected by the SPARQL gate")
    func rejectsNonTaxon() async throws {
        let resolution = try await provider(FixtureTransport(search: "search-non-taxon", gate: "gate-empty", entities: "entities-honey-buzzard"))
            .resolve(query: #require(TaxonSearchQuery("not a taxon")), languages: [english])
        #expect(resolution == .noMatch)
    }

    @Test("Taxon validation overlaps the SPARQL gate and entity hydration")
    func overlapsGateAndEntityHydration() async throws {
        let overlapBarrier = RequestOverlapBarrier()
        let transport = FixtureTransport(
            search: "search-wespendief",
            gate: "gate-honey-buzzard",
            entities: "entities-honey-buzzard",
            overlapBarrier: overlapBarrier
        )

        let resolution = try await provider(transport).resolve(
            query: #require(TaxonSearchQuery("wespendief")),
            languages: [dutch]
        )

        guard case .resolved = resolution else {
            Issue.record("Expected fixture resolution")
            return
        }
        #expect(overlapBarrier.startedRequestKinds == Set(["gate", "entities"]))
        #expect(overlapBarrier.releasedAfterBothStarted)
    }

    @Test("Configured-language searches overlap")
    func overlapsConfiguredLanguageSearches() async throws {
        let searchCoordinator = SearchRequestCoordinator(
            expectedLanguages: ["en", "fr"],
            releaseOrder: ["en", "fr"]
        )
        let transport = FixtureTransport(
            search: "search-ambiguous",
            gate: "gate-ambiguous",
            entities: "entities-ambiguous",
            searchCoordinator: searchCoordinator
        )

        _ = try await provider(transport).resolve(
            query: #require(TaxonSearchQuery("Common Swift")),
            languages: [english, french]
        )

        #expect(searchCoordinator.startedLanguages == Set(["en", "fr"]))
        #expect(searchCoordinator.releasedAfterAllStarted)
    }

    @Test("Candidate merging preserves configured-language order")
    func preservesLanguageOrderWhenSearchesCompleteOutOfOrder() async throws {
        let searchCoordinator = SearchRequestCoordinator(
            expectedLanguages: ["en", "fr"],
            releaseOrder: ["fr", "en"]
        )
        let transport = FixtureTransport(
            search: "search-ambiguous",
            gate: "gate-ambiguous",
            entities: "entities-ambiguous",
            searchByLanguage: [
                "en": "search-q100",
                "fr": "search-q200"
            ],
            searchCoordinator: searchCoordinator
        )

        let resolution = try await provider(transport, candidateLimit: 1).resolve(
            query: #require(TaxonSearchQuery("Common Swift")),
            languages: [english, french]
        )

        guard case let .resolved(taxon) = resolution else {
            Issue.record("Expected the first configured language's candidate")
            return
        }
        #expect(searchCoordinator.deliveredLanguages == ["fr", "en"])
        #expect(taxon.wikidataID.rawValue == "Q100")
    }

    @Test("Candidate interleaving retains an exact match from a later language")
    func interleavesCandidatesAcrossConfiguredLanguages() async throws {
        let transport = FixtureTransport(
            search: "search-ambiguous",
            gate: "gate-honey-buzzard",
            entities: "entities-honey-buzzard",
            searchByLanguage: [
                "en": "search-ambiguous",
                "nl": "search-wespendief"
            ]
        )

        let resolution = try await provider(transport, candidateLimit: 2).resolve(
            query: #require(TaxonSearchQuery("wespendief")),
            languages: [english, dutch]
        )

        guard case let .resolved(taxon) = resolution else {
            Issue.record("Expected the interleaved Dutch candidate to resolve")
            return
        }
        #expect(taxon.wikidataID.rawValue == "Q170466")
        #expect(taxon.preferredName(for: dutch)?.value == "Wespendief")
    }

    @Test("Rate limiting preserves Retry-After")
    func mapsRateLimit() async throws {
        let transport = FixtureTransport(search: "search-wespendief", gate: "gate-honey-buzzard", entities: "entities-honey-buzzard", statusCode: 429, retryAfter: "12")
        await #expect(throws: TaxonResolutionError.rateLimited(retryAfter: 12)) {
            try await provider(transport).resolve(query: #require(TaxonSearchQuery("wespendief")), languages: [english])
        }
    }

    private func provider(
        _ transport: FixtureTransport,
        candidateLimit: Int = 20
    ) -> WikidataProvider {
        WikidataProvider(
            session: transport.session,
            configuration: .init(
                actionAPIBaseURL: transport.actionAPIBaseURL,
                queryServiceURL: transport.queryServiceURL,
                userAgent: "TaxonTests/1.0 (fixture)",
                candidateLimit: candidateLimit
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

    private func europeanBeeEater(languages: [TaxonLanguage]) async throws -> Taxon? {
        try await provider(
            FixtureTransport(
                search: "search-scientific",
                gate: "gate-european-bee-eater",
                entities: "entities-european-bee-eater"
            )
        ).taxon(for: WikidataID(rawValue: "Q170718")!, languages: languages)
    }
}

private final class FixtureTransport: @unchecked Sendable {
    let session: URLSession
    let actionAPIBaseURL: URL
    let queryServiceURL: URL
    private let fixtures: [String: Data]
    private let statusCode: Int
    private let retryAfter: String?
    private let overlapBarrier: RequestOverlapBarrier?
    private let searchCoordinator: SearchRequestCoordinator?
    private let lock = NSLock()
    private(set) var userAgents: [String] = []

    init(
        search: String,
        gate: String,
        entities: String,
        statusCode: Int = 200,
        retryAfter: String? = nil,
        overlapBarrier: RequestOverlapBarrier? = nil,
        searchByLanguage: [String: String] = [:],
        searchCoordinator: SearchRequestCoordinator? = nil
    ) {
        let identifier = UUID().uuidString.lowercased()
        self.actionAPIBaseURL = URL(string: "https://action-\(identifier).fixture/w/api.php")!
        self.queryServiceURL = URL(string: "https://query-\(identifier).fixture/sparql")!
        var fixtures = ["search": fixture(search), "gate": fixture(gate), "entities": fixture(entities)]
        for (language, fixtureName) in searchByLanguage {
            fixtures["search-\(language)"] = fixture(fixtureName)
        }
        self.fixtures = fixtures
        self.statusCode = statusCode
        self.retryAfter = retryAfter
        self.overlapBarrier = overlapBarrier
        self.searchCoordinator = searchCoordinator
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureURLProtocol.self]
        self.session = URLSession(configuration: configuration)
        FixtureURLProtocol.install(transport: self)
    }

    fileprivate func response(for request: URLRequest) -> (kind: String, language: String?, response: HTTPURLResponse, data: Data) {
        lock.lock()
        userAgents.append(request.value(forHTTPHeaderField: "User-Agent") ?? "")
        lock.unlock()
        let queryItems = request.url.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems
        } ?? []
        let action = queryItems.first(where: { $0.name == "action" })?.value
        let language = queryItems.first(where: { $0.name == "language" })?.value
        let kind = request.url?.host == queryServiceURL.host
            ? "gate"
            : action == "wbgetentities" ? "entities" : "search"
        let fixtureKey = kind == "search" && language.map({ fixtures["search-\($0)"] != nil }) == true
            ? "search-\(language!)"
            : kind
        var headers = [String: String]()
        if let retryAfter { headers["Retry-After"] = retryAfter }
        let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: headers)!
        return (kind, language, response, fixtures[fixtureKey]!)
    }

    fileprivate func deliverWhenReady(kind: String, language: String?, _ delivery: @escaping () -> Void) {
        if kind == "search", let language, let searchCoordinator {
            searchCoordinator.arrive(language: language, delivery: delivery)
            return
        }
        guard let overlapBarrier, kind == "gate" || kind == "entities" else {
            delivery()
            return
        }
        overlapBarrier.arrive(kind: kind, delivery: delivery)
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
        let result = activeTransport.response(for: request)
        activeTransport.deliverWhenReady(kind: result.kind, language: result.language) { [weak self] in
            guard let self else { return }
            self.client?.urlProtocol(self, didReceive: result.response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: result.data)
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

private final class SearchRequestCoordinator: @unchecked Sendable {
    private let expectedLanguages: Set<String>
    private let releaseOrder: [String]
    private let lock = NSLock()
    private var deliveries: [String: () -> Void] = [:]
    private var started = Set<String>()
    private var delivered: [String] = []
    private var didReleaseAfterAllStarted = false

    init(expectedLanguages: Set<String>, releaseOrder: [String]) {
        self.expectedLanguages = expectedLanguages
        self.releaseOrder = releaseOrder
    }

    var startedLanguages: Set<String> {
        lock.withLock { started }
    }

    var deliveredLanguages: [String] {
        lock.withLock { delivered }
    }

    var releasedAfterAllStarted: Bool {
        lock.withLock { didReleaseAfterAllStarted }
    }

    func arrive(language: String, delivery: @escaping () -> Void) {
        let pending: [(String, () -> Void)] = lock.withLock {
            started.insert(language)
            deliveries[language] = delivery
            guard expectedLanguages.isSubset(of: started) else { return [] }
            didReleaseAfterAllStarted = true
            let pending = releaseOrder.compactMap { language in
                deliveries.removeValue(forKey: language).map { (language, $0) }
            }
            return pending
        }

        for item in pending {
            lock.withLock { delivered.append(item.0) }
            item.1()
        }
    }
}

private final class RequestOverlapBarrier: @unchecked Sendable {
    private let lock = NSLock()
    private var deliveries: [String: () -> Void] = [:]
    private var started = Set<String>()
    private var didReleaseAfterBothStarted = false

    var startedRequestKinds: Set<String> {
        lock.withLock { started }
    }

    var releasedAfterBothStarted: Bool {
        lock.withLock { didReleaseAfterBothStarted }
    }

    func arrive(kind: String, delivery: @escaping () -> Void) {
        let (pending, needsFallback): ([() -> Void], Bool) = lock.withLock {
            started.insert(kind)
            deliveries[kind] = delivery
            guard deliveries.keys.contains("gate"), deliveries.keys.contains("entities") else {
                return ([], deliveries.count == 1)
            }
            didReleaseAfterBothStarted = true
            let pending = Array(deliveries.values)
            deliveries.removeAll()
            return (pending, false)
        }
        pending.forEach { $0() }
        if needsFallback {
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(500)) { [weak self] in
                self?.releasePending()
            }
        }
    }

    private func releasePending() {
        let pending: [() -> Void] = lock.withLock {
            let pending = Array(deliveries.values)
            deliveries.removeAll()
            return pending
        }
        pending.forEach { $0() }
    }
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
