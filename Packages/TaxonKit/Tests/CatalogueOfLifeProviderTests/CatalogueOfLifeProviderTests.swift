import Foundation
import Testing
@testable import CatalogueOfLifeProvider
import TaxonDomain

@MainActor
struct CatalogueOfLifeProviderTests {
    private let english = TaxonLanguage(rawValue: "en")!
    private let french = TaxonLanguage(rawValue: "fr")!
    private let dutch = TaxonLanguage(rawValue: "nl")!
    private let italianItaly = TaxonLanguage(rawValue: "it-IT")!

    @Test("Verified COL records map ISO-639-3 vernaculars in configured order")
    func mapsVerifiedNames() async throws {
        let transport = FixtureTransport(fixture: "search-bee-eater")
        let names = try await provider(transport).names(
            for: beeEater(),
            languages: [italianItaly, dutch, english, french]
        )

        #expect(names.map(\.value) == [
            "Gruccione",
            "Bijeneter",
            "European Bee-eater",
            "Bee-eater",
            "Guêpier d'Europe"
        ])
        #expect(names.map(\.language) == [
            italianItaly, dutch, english, english, french
        ])
        #expect(names.first?.regionCode == "IT")
        #expect(names.first?.isPreferred == true)
        #expect(names.allSatisfy { $0.source == .catalogueOfLife })
        #expect(names.contains { $0.value == "Merops apiaster" } == false)
        #expect(names.contains { $0.value == "Wrong taxon name" } == false)
        #expect(names.contains { $0.value == "Synonym result name" } == false)
    }

    @Test("Enrichment preserves Wikidata names and appends only new COL values")
    func enrichesWithoutReplacingExistingNames() async throws {
        let existing = LocalizedTaxonName(
            language: english,
            value: "European Bee-eater",
            source: .wikidata,
            isPreferred: true
        )!
        let taxon = beeEater(names: [existing])
        let enriched = try await provider(
            FixtureTransport(fixture: "search-bee-eater")
        ).enrich(taxon, languages: [english, dutch])

        #expect(enriched.identity == taxon.identity)
        #expect(enriched.names.first == existing)
        #expect(enriched.names.filter { $0.value == "European Bee-eater" }.count == 1)
        #expect(enriched.preferredName(for: english) == existing)
        #expect(enriched.preferredName(for: dutch)?.value == "Bijeneter")
    }

    @Test("A scientific-name or Q-ID mismatch cannot enrich a taxon")
    func rejectsUnverifiedMatches() async throws {
        let names = try await provider(
            FixtureTransport(fixture: "search-unverified")
        ).names(for: beeEater(), languages: [english])
        #expect(names.isEmpty)
    }

    @Test("An empty COL search remains an ordinary missing enrichment")
    func preservesEmptySearch() async throws {
        let names = try await provider(
            FixtureTransport(fixture: "search-empty")
        ).names(for: beeEater(), languages: [english])
        #expect(names.isEmpty)
    }

    @Test("A language-less unrelated vernacular does not discard a valid localized name")
    func ignoresLanguageLessVernacularFromUnrelatedCandidate() async throws {
        let honeyBee = Taxon(
            identity: TaxonIdentity(
                wikidataID: WikidataID(rawValue: "Q30034")!,
                scientificName: ScientificName("Apis mellifera")!
            ),
            rank: TaxonomicRank("species")
        )

        let names = try await provider(
            FixtureTransport(fixture: "search-honey-bee-language-less-candidate")
        ).names(for: honeyBee, languages: [italianItaly])

        #expect(names.map(\.value) == ["Ape europea"])
        #expect(names.map(\.language) == [italianItaly])
        #expect(names.allSatisfy { $0.source == .catalogueOfLife })
    }

    @Test("Release attribution decodes the current COL XR metadata shape")
    func decodesReleaseAttribution() async throws {
        let transport = FixtureTransport(fixture: "dataset-release-current")

        let attribution = try await provider(transport).releaseAttribution()

        #expect(attribution.version == "2026-07-17 XR")
        #expect(attribution.doi == "10.48580/dgykv")
        #expect(attribution.license == .creativeCommonsAttribution4)
        #expect(attribution.doiURL?.absoluteString == "https://doi.org/10.48580/dgykv")
        #expect(
            attribution.licenseURL?.absoluteString
                == "https://creativecommons.org/licenses/by/4.0/"
        )

        let request = try #require(transport.lastRequest)
        #expect(request.url?.path == "/dataset/3LXR")
        #expect(request.url?.query == nil)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "TaxonTests/1.0 (fixture)")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test("Release attribution preserves an unrecognized license")
    func preservesUnknownReleaseLicense() async throws {
        let attribution = try await provider(
            FixtureTransport(fixture: "dataset-release-unknown-license")
        ).releaseAttribution()

        #expect(attribution.license == .unknown("Open Data Commons Attribution License"))
        #expect(attribution.licenseURL == nil)
    }

    @Test("Requests identify Taxon and use a bounded accepted-name search")
    func formsExpectedRequest() async throws {
        let transport = FixtureTransport(fixture: "search-bee-eater")
        _ = try await provider(transport, candidateLimit: 7).names(
            for: beeEater(),
            languages: [english]
        )

        let request = try #require(transport.lastRequest)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "TaxonTests/1.0 (fixture)")
        #expect(request.url?.path == "/dataset/3LXR/nameusage/search")
        let items = URLComponents(
            url: try #require(request.url),
            resolvingAgainstBaseURL: false
        )?.queryItems ?? []
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value) })
        #expect(query["q"] == "Merops apiaster")
        #expect(query["status"] == "accepted")
        #expect(query["limit"] == "7")
    }

    @Test("Rate limiting preserves Retry-After")
    func mapsRateLimit() async throws {
        let transport = FixtureTransport(
            fixture: "search-empty",
            statusCode: 429,
            retryAfter: "12"
        )
        await #expect(throws: TaxonResolutionError.rateLimited(retryAfter: 12)) {
            try await provider(transport).names(
                for: beeEater(),
                languages: [english]
            )
        }
    }

    @Test("Resolver composition treats enrichment failure as best effort")
    func resolverFallsBackToBaseTaxon() async throws {
        let taxon = beeEater()
        let transport = FixtureTransport(
            fixture: "search-empty",
            statusCode: 503
        )
        let resolver = CatalogueOfLifePrimaryResolver(
            secondary: StubResolver(resolution: .resolved(taxon)),
            catalogueOfLife: provider(transport)
        )

        let resolution = try await resolver.resolve(
            query: TaxonSearchQuery("Merops apiaster")!,
            languages: [english]
        )
        #expect(resolution == .resolved(taxon))
    }

    @Test("Catalogue of Life resolves an exact Dutch vernacular before Wikidata text search")
    func resolvesKoeFromVernacularIndex() async throws {
        let transport = FixtureTransport(routes: [
            "/dataset/3LXR/nameusage/search": "search-empty",
            "/dataset/3LXR/vernacular": "vernacular-koe",
            "/dataset/3LXR/taxon/MLQ5": "taxon-bos-taurus",
            "/dataset/3LXR/taxon/MLQ5/vernacular": "names-bos-taurus"
        ])
        let wikidataTaxon = cattle()
        let secondary = HydratingStubResolver(
            resolution: .noMatch,
            taxa: [wikidataTaxon.wikidataID: wikidataTaxon]
        )
        let resolver = CatalogueOfLifePrimaryResolver(
            secondary: secondary,
            catalogueOfLife: provider(transport)
        )

        let resolution = try await resolver.resolve(
            query: TaxonSearchQuery("koe")!,
            languages: [dutch, english]
        )

        guard case let .resolved(taxon) = resolution else {
            Issue.record("Expected an exact COL vernacular resolution")
            return
        }
        #expect(taxon.wikidataID.rawValue == "Q19610691")
        #expect(taxon.scientificName.value == "Bos taurus")
        let dutchNames = taxon.names.filter { $0.language == dutch }
        #expect(dutchNames.contains {
            $0.value == "Koe" && $0.source == .catalogueOfLife
        })
        #expect(await secondary.resolveCallCount == 0)
    }

    @Test("An exact vernacular shared by multiple COL taxa remains ambiguous")
    func preservesCowAmbiguity() async throws {
        let transport = FixtureTransport(routes: [
            "/dataset/3LXR/nameusage/search": "search-empty",
            "/dataset/3LXR/vernacular": "vernacular-cow",
            "/dataset/3LXR/taxon/3BQW": "taxon-bos",
            "/dataset/3LXR/taxon/3BQW/vernacular": "names-bos",
            "/dataset/3LXR/taxon/MLQ5": "taxon-bos-taurus",
            "/dataset/3LXR/taxon/MLQ5/vernacular": "names-bos-taurus"
        ])
        let genus = bos()
        let species = cattle()
        let resolver = CatalogueOfLifePrimaryResolver(
            secondary: HydratingStubResolver(
                resolution: .noMatch,
                taxa: [
                    genus.wikidataID: genus,
                    species.wikidataID: species
                ]
            ),
            catalogueOfLife: provider(transport)
        )

        let resolution = try await resolver.resolve(
            query: TaxonSearchQuery("cow")!,
            languages: [english, dutch]
        )

        guard case let .candidates(candidates) = resolution else {
            Issue.record("Expected explicit selection for two exact COL matches")
            return
        }
        let scientificNames = candidates.map {
            $0.taxon.scientificName.value
        }
        #expect(scientificNames == [
            "Bos", "Bos taurus"
        ])
        #expect(candidates.allSatisfy {
            $0.matchKind == TaxonMatchKind.exactLocalizedName
                && $0.matchedName == "Cow"
        })
    }

    @Test("A COL vernacular without a linked Q-ID uses secondary discovery")
    func fallsBackWhenCatalogueIdentityCannotBeVerified() async throws {
        let transport = FixtureTransport(routes: [
            "/dataset/3LXR/nameusage/search": "search-empty",
            "/dataset/3LXR/vernacular": "vernacular-unlinked",
            "/dataset/3LXR/taxon/UNLINKED": "taxon-unlinked",
            "/dataset/3LXR/taxon/UNLINKED/vernacular": "names-unlinked"
        ])
        let fallbackTaxon = beeEater()
        let secondary = HydratingStubResolver(
            resolution: .resolved(fallbackTaxon),
            taxa: [:]
        )
        let resolver = CatalogueOfLifePrimaryResolver(
            secondary: secondary,
            catalogueOfLife: provider(transport)
        )

        let resolution = try await resolver.resolve(
            query: TaxonSearchQuery("unlinked name")!,
            languages: [english]
        )

        #expect(resolution == .resolved(fallbackTaxon))
        #expect(await secondary.resolveCallCount == 1)
    }

    private func provider(
        _ transport: FixtureTransport,
        candidateLimit: Int = 20
    ) -> CatalogueOfLifeProvider {
        CatalogueOfLifeProvider(
            session: transport.session,
            configuration: .init(
                baseURL: transport.baseURL,
                datasetAlias: "3LXR",
                userAgent: "TaxonTests/1.0 (fixture)",
                candidateLimit: candidateLimit
            )
        )
    }

    private func beeEater(
        names: [LocalizedTaxonName] = []
    ) -> Taxon {
        Taxon(
            identity: TaxonIdentity(
                wikidataID: WikidataID(rawValue: "Q170718")!,
                scientificName: ScientificName("Merops apiaster")!
            ),
            rank: TaxonomicRank("species"),
            names: names
        )
    }

    private func cattle() -> Taxon {
        Taxon(
            identity: TaxonIdentity(
                wikidataID: WikidataID(rawValue: "Q19610691")!,
                scientificName: ScientificName("Bos taurus")!
            ),
            rank: TaxonomicRank("species")
        )
    }

    private func bos() -> Taxon {
        Taxon(
            identity: TaxonIdentity(
                wikidataID: WikidataID(rawValue: "Q237993")!,
                scientificName: ScientificName("Bos")!
            ),
            rank: TaxonomicRank("genus")
        )
    }
}

private struct StubResolver: TaxonResolving {
    let resolution: TaxonResolution

    func resolve(
        query: TaxonSearchQuery,
        languages: [TaxonLanguage]
    ) async throws -> TaxonResolution {
        resolution
    }

    func taxon(
        for wikidataID: WikidataID,
        languages: [TaxonLanguage]
    ) async throws -> Taxon? {
        guard case let .resolved(taxon) = resolution else { return nil }
        return taxon.wikidataID == wikidataID ? taxon : nil
    }
}

private actor HydratingStubResolver: TaxonResolving {
    let resolution: TaxonResolution
    let taxa: [WikidataID: Taxon]
    private(set) var resolveCallCount = 0

    init(
        resolution: TaxonResolution,
        taxa: [WikidataID: Taxon]
    ) {
        self.resolution = resolution
        self.taxa = taxa
    }

    func resolve(
        query: TaxonSearchQuery,
        languages: [TaxonLanguage]
    ) async throws -> TaxonResolution {
        resolveCallCount += 1
        return resolution
    }

    func taxon(
        for wikidataID: WikidataID,
        languages: [TaxonLanguage]
    ) async throws -> Taxon? {
        taxa[wikidataID]
    }
}

private final class FixtureTransport: @unchecked Sendable {
    let session: URLSession
    let baseURL: URL

    private let data: Data
    private let routedData: [String: Data]
    private let statusCode: Int
    private let retryAfter: String?
    private let lock = NSLock()
    private var recordedRequest: URLRequest?

    var lastRequest: URLRequest? {
        lock.withLock { recordedRequest }
    }

    init(
        fixture name: String,
        statusCode: Int = 200,
        retryAfter: String? = nil
    ) {
        let identifier = UUID().uuidString.lowercased()
        self.baseURL = URL(string: "https://col-\(identifier).fixture")!
        self.data = Self.fixture(name)
        self.routedData = [:]
        self.statusCode = statusCode
        self.retryAfter = retryAfter

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureURLProtocol.self]
        self.session = URLSession(configuration: configuration)
        FixtureURLProtocol.install(self)
    }

    init(routes: [String: String]) {
        let identifier = UUID().uuidString.lowercased()
        self.baseURL = URL(string: "https://col-\(identifier).fixture")!
        self.data = Self.fixture("search-empty")
        self.routedData = routes.mapValues(Self.fixture)
        self.statusCode = 200
        self.retryAfter = nil

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureURLProtocol.self]
        self.session = URLSession(configuration: configuration)
        FixtureURLProtocol.install(self)
    }

    fileprivate func response(
        for request: URLRequest
    ) -> (HTTPURLResponse, Data) {
        lock.withLock { recordedRequest = request }
        var headers = [String: String]()
        if let retryAfter { headers["Retry-After"] = retryAfter }
        return (
            HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: headers
            )!,
            routedData[request.url?.path ?? ""] ?? data
        )
    }

    private static func fixture(_ name: String) -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json")!
        return try! Data(contentsOf: url)
    }
}

private final class FixtureURLProtocol: URLProtocol {
    private static let registry = FixtureRegistry()

    static func install(_ transport: FixtureTransport) {
        registry.insert(transport)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard
            let host = request.url?.host,
            let transport = Self.registry.transport(for: host)
        else {
            return
        }
        let (response, data) = transport.response(for: request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private final class FixtureRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var transports = [String: FixtureTransport]()

    func insert(_ transport: FixtureTransport) {
        lock.withLock {
            transports[transport.baseURL.host!] = transport
        }
    }

    func transport(for host: String) -> FixtureTransport? {
        lock.withLock { transports[host] }
    }
}
