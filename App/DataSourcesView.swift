import SwiftUI
import CatalogueOfLifeProvider

struct DataSourcesView: View {
    private enum ReleaseState {
        case loading
        case loaded(CatalogueOfLifeProvider.ReleaseAttribution)
        case unavailable
    }

    let catalogueOfLife: CatalogueOfLifeProvider
    @State private var releaseState = ReleaseState.loading

    private let catalogueOfLifeURL = URL(
        string: "https://www.catalogueoflife.org"
    )!
    private let citationURL = URL(
        string: "https://www.catalogueoflife.org/howto/cite"
    )!
    private let feedbackURL = URL(
        string: "https://www.catalogueoflife.org/howto/contribute"
    )!
    private let wikidataURL = URL(
        string: "https://www.wikidata.org"
    )!

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 5) {
                    Link("Catalogue of Life", destination: catalogueOfLifeURL)
                        .font(.headline)
                    Text("Catalogue of Life Foundation")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Taxonomic and vernacular-name data")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)

                releaseDetails

                Link("Citation guidance", destination: citationURL)

                Link(destination: feedbackURL) {
                    Label(
                        "Report source-data issues to Catalogue of Life",
                        systemImage: "arrow.up.right.square"
                    )
                }
            } header: {
                Text("Catalogue of Life")
            } footer: {
                Text(
                    "Catalogue of Life may contain errors or omissions. "
                    + "Taxon displays this external data and cannot correct its source records. "
                    + "Please send taxonomic or name corrections to Catalogue of Life."
                )
            }

            Section("How Taxon uses the data") {
                Text(
                    "Names may be normalized, filtered, and combined with Wikidata."
                )
            }

            Section {
                Link(destination: wikidataURL) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Wikidata")
                            .foregroundStyle(.tint)
                        Text(
                            "Canonical taxon verification, localized names, and Wikipedia links"
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Wikidata")
            }
        }
        .navigationTitle("Data Sources")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadReleaseAttribution() }
    }

    @ViewBuilder
    private var releaseDetails: some View {
        switch releaseState {
        case .loading:
            HStack(spacing: 10) {
                ProgressView()
                Text("Loading current release…")
                    .foregroundStyle(.secondary)
            }
        case let .loaded(attribution):
            VStack(alignment: .leading, spacing: 6) {
                Text("Release \(attribution.version)")
                if let doiURL = attribution.doiURL {
                    Link("DOI \(attribution.doi)", destination: doiURL)
                } else {
                    Text("DOI \(attribution.doi)")
                }
                licenseView(attribution.license)
            }
        case .unavailable:
            VStack(alignment: .leading, spacing: 4) {
                Text("Current release details unavailable")
                    .foregroundStyle(.secondary)
                Text("Attribution and reporting links remain available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func licenseView(
        _ license: CatalogueOfLifeProvider.ReleaseAttribution.License
    ) -> some View {
        switch license {
        case .creativeCommonsAttribution4:
            Link(
                "Creative Commons Attribution 4.0",
                destination: URL(
                    string: "https://creativecommons.org/licenses/by/4.0/"
                )!
            )
        case .creativeCommonsZero1:
            Link(
                "CC0 1.0 Universal",
                destination: URL(
                    string: "https://creativecommons.org/publicdomain/zero/1.0/"
                )!
            )
        case let .unknown(value):
            Text("License: \(value)")
        }
    }

    private func loadReleaseAttribution() async {
        do {
            releaseState = .loaded(
                try await catalogueOfLife.releaseAttribution()
            )
        } catch is CancellationError {
            return
        } catch {
            releaseState = .unavailable
        }
    }
}
