import SwiftUI
import TaxonDomain

struct ShareView: View {
    @Bindable var model: ShareLookupModel
    let close: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                switch model.state {
                case .loadingInput:
                    ProgressView("Reading shared text…")
                case .resolving:
                    ProgressView("Resolving taxon…")
                case let .candidates(candidates):
                    candidateList(candidates)
                case let .resolved(taxon):
                    result(taxon)
                case .noMatch:
                    ContentUnavailableView("No matching taxon", systemImage: "questionmark.circle")
                case let .failed(message):
                    ContentUnavailableView("Lookup unavailable", systemImage: "exclamationmark.triangle", description: Text(message))
                }
            }
            .navigationTitle("Taxon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close", action: close)
                }
            }
        }
    }

    private func candidateList(_ candidates: [TaxonCandidate]) -> some View {
        List(candidates) { candidate in
            Button {
                model.select(candidate)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(candidate.taxon.scientificName.value).italic()
                    if let matchedName = candidate.matchedName { Text(matchedName).foregroundStyle(.secondary) }
                    if let rank = candidate.taxon.rank { Text(rank.name.capitalized).font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
    }

    private func result(_ taxon: Taxon) -> some View {
        let rows = ShareResultFormatter.rows(for: taxon, configuration: model.outputConfiguration)
        return List {
            Section("Names") {
                ForEach(rows) { row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(localizedLabel(row.label)).foregroundStyle(.secondary)
                        Spacer()
                        if let value = row.value {
                            Text(value).italic(row.isScientific).multilineTextAlignment(.trailing)
                            Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = value }
                                .labelStyle(.iconOnly)
                        } else {
                            Text("Not available").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section {
                Button("Copy all", systemImage: "doc.on.doc.fill") {
                    UIPasteboard.general.string = ShareResultFormatter.formattedAvailableRows(rows)
                }
            }
        }
    }

    private func localizedLabel(_ code: String) -> String {
        guard code != "Scientific" else { return code }
        return Locale.current.localizedString(forLanguageCode: code) ?? code
    }
}
