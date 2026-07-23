import SwiftUI
import TaxonDomain

struct TaxonSearchView: View {
    @Bindable var model: SearchModel
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            Group {
                switch model.state {
                case .idle:
                    ContentUnavailableView(
                        "Find a taxon",
                        systemImage: "leaf",
                        description: Text("Search a common or scientific name.")
                    )
                case .loading:
                    ProgressView("Resolving taxon…")
                case let .candidates(candidates):
                    CandidateList(candidates: candidates, select: model.select)
                case let .resolved(taxon):
                    TaxonResultView(
                        taxon: taxon,
                        configuration: model.outputConfiguration,
                        preferredWikipediaLanguage: model.preferredWikipediaLanguage
                    )
                case .noMatch:
                    ContentUnavailableView.search(text: model.queryText)
                case let .failed(message):
                    ContentUnavailableView("Lookup unavailable", systemImage: "wifi.exclamationmark", description: Text(message))
                }
            }
            .navigationTitle("Taxon")
            .searchable(text: $model.queryText, prompt: "Common or scientific name")
            .onChange(of: model.queryText) { _, _ in model.searchTextDidChange() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Output languages", systemImage: "slider.horizontal.3") {
                        showingSettings = true
                    }
                    .accessibilityLabel("Configure output languages")
                }
            }
            .sheet(isPresented: $showingSettings) {
                OutputLanguageSettings(model: model)
            }
        }
    }
}

private struct CandidateList: View {
    let candidates: [TaxonCandidate]
    let select: (TaxonCandidate) -> Void

    var body: some View {
        List(candidates) { candidate in
            Button {
                select(candidate)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(candidate.taxon.scientificName.value)
                        .font(.headline)
                        .italic()
                    if let matchedName = candidate.matchedName {
                        Text(matchedName)
                            .foregroundStyle(.secondary)
                    }
                    if let rank = candidate.taxon.rank {
                        Text(rank.name.capitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityLabel(candidate.taxon.scientificName.value)
        }
    }
}

private struct TaxonResultView: View {
    let taxon: Taxon
    let configuration: OutputLanguageConfiguration
    let preferredWikipediaLanguage: TaxonLanguage?

    var body: some View {
        List {
            if let rank = taxon.rank {
                Section {
                    LabeledContent("Rank", value: rank.name.capitalized)
                    LabeledContent("Wikidata", value: taxon.wikidataID.rawValue)
                }
            }

            Section("Names") {
                ForEach(configuration.displayRows(for: taxon)) { row in
                    NameRow(row: row)
                }
            }

            if let sitelink = taxon.wikipediaSitelink(
                preferredLanguage: preferredWikipediaLanguage,
                configuredLanguages: configuration.languages
            ) {
                Section {
                    Link(destination: sitelink.url) {
                        Label("Open in Wikipedia", systemImage: "safari")
                    }
                    .accessibilityHint("Opens the \(sitelink.language.rawValue) Wikipedia article")
                }
            }
        }
        .navigationTitle(taxon.scientificName.value)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct NameRow: View {
    let row: TaxonDisplayRow

    private var label: String {
        switch row {
        case .scientific: return "Scientific"
        case let .localized(language, _):
            return Locale.current.localizedString(forLanguageCode: language.baseLanguageCode) ?? language.rawValue
        }
    }

    private var name: String? {
        switch row {
        case let .scientific(scientificName): return scientificName.value
        case let .localized(_, localizedName): return localizedName?.value
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            if let name {
                Text(name)
                    .multilineTextAlignment(.trailing)
                    .italic(isScientific)
                Button("Copy", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = name
                }
                .labelStyle(.iconOnly)
                .accessibilityLabel("Copy \(label) name")
            } else {
                Text("Not available")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(label) name not available")
            }
        }
    }

    private var isScientific: Bool {
        if case .scientific = row { return true }
        return false
    }
}

private struct OutputLanguageSettings: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: SearchModel
    @State private var languageCode = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Languages") {
                    ForEach(model.configuredLanguages) { language in
                        Text(Locale.current.localizedString(forLanguageCode: language.baseLanguageCode) ?? language.rawValue)
                    }
                    .onDelete(perform: model.removeLanguages)
                    .onMove(perform: model.moveLanguages)

                    HStack {
                        TextField("Language code", text: $languageCode)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Add") {
                            model.addLanguage(code: languageCode)
                            languageCode = ""
                        }
                        .disabled(TaxonLanguage(rawValue: languageCode) == nil)
                    }
                }

                Section("Scientific name") {
                    Picker("Position", selection: $model.scientificNamePosition) {
                        Text("First").tag(ScientificNamePosition.first)
                        Text("Last").tag(ScientificNamePosition.last)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Wikipedia") {
                    Picker("Preferred language", selection: $model.preferredWikipediaLanguage) {
                        Text("Configured fallback").tag(TaxonLanguage?.none)
                        ForEach(model.configuredLanguages) { language in
                            Text(Locale.current.localizedString(forLanguageCode: language.baseLanguageCode) ?? language.rawValue)
                                .tag(Optional(language))
                        }
                    }
                }
            }
            .navigationTitle("Output languages")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
        }
    }
}
