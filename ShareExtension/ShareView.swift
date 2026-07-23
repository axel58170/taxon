import SwiftUI
import TaxonDomain

struct ShareView: View {
    @Bindable var model: ShareLookupModel
    let close: () -> Void
    @State private var copiedAll = false

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
                    ShareNameRow(row: row, label: localizedLabel(row))
                }
            }
            Section {
                Button {
                    UIPasteboard.general.string = ShareResultFormatter.formattedAvailableRows(rows)
                    copiedAll = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copiedAll = false
                    }
                } label: {
                    Label(
                        copiedAll ? String(localized: "Copied") : String(localized: "Copy all"),
                        systemImage: copiedAll ? "checkmark.circle.fill" : "doc.on.doc.fill"
                    )
                }
                .foregroundStyle(copiedAll ? Color.green : Color.accentColor)
                .contentTransition(.symbolEffect(.replace))
                .sensoryFeedback(.success, trigger: copiedAll)
            }
        }
    }

    private func localizedLabel(_ row: ShareResultRow) -> String {
        guard !row.isScientific else { return row.label }
        return Locale.current.localizedString(forLanguageCode: row.label) ?? row.label
    }
}

private struct ShareNameRow: View {
    let row: ShareResultRow
    let label: String
    @State private var copied = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            if let value = row.value {
                Text(value).italic(row.isScientific).multilineTextAlignment(.trailing)
                Button {
                    UIPasteboard.general.string = value
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                } label: {
                    Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                }
                .foregroundStyle(copied ? Color.green : Color.accentColor)
                .accessibilityLabel(
                    copied ? String(localized: "Copied") : String(localized: "Copy")
                )
                .sensoryFeedback(.success, trigger: copied)
            } else {
                Text("Not available").foregroundStyle(.secondary)
            }
        }
    }
}
