import SwiftUI
import CatalogueOfLifeProvider
import TaxonDomain

struct TaxonSearchView: View {
    @Bindable var model: SearchModel
    let catalogueOfLife: CatalogueOfLifeProvider
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            Group {
                switch model.state {
                case .idle:
                    TaxonSearchWelcome(
                        languages: model.configuredLanguages,
                        resolve: model.resolveImmediately
                    )
                case .loading:
                    ProgressView("Resolving taxon…")
                case let .candidates(candidates):
                    CandidateList(candidates: candidates, select: model.select)
                case let .resolved(taxon):
                    TaxonResultView(
                        taxon: taxon,
                        configuration: model.outputConfiguration,
                        preferredWikipediaLanguage: model.preferredWikipediaLanguage,
                        startNewSearch: model.startNewSearch
                    )
                case .noMatch:
                    ContentUnavailableView.search(text: model.queryText)
                case let .failed(message):
                    ContentUnavailableView("Lookup unavailable", systemImage: "wifi.exclamationmark", description: Text(message))
                }
            }
            .navigationTitle("Taxon")
            .background {
                SearchDismissObserver(shouldDismiss: isShowingResolvedTaxon)
            }
            .searchable(text: $model.queryText, prompt: "Name in any configured language")
            .onChange(of: model.queryText) { _, _ in model.searchTextDidChange() }
            .onSubmit(of: .search) {
                Task { await model.resolveImmediately(model.queryText) }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") {
                        showingSettings = true
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showingSettings) {
                AppSettingsView(
                    model: model,
                    catalogueOfLife: catalogueOfLife
                )
            }
        }
    }

    private var isShowingResolvedTaxon: Bool {
        if case .resolved = model.state { return true }
        return false
    }
}

private struct TaxonSearchWelcome: View {
    let languages: [TaxonLanguage]
    let resolve: (String) async -> Void

    private let examples = [
        TaxonSearchExample(name: String(localized: "English oak"), scientificName: "Quercus robur", symbol: "tree"),
        TaxonSearchExample(name: String(localized: "Common daisy"), scientificName: "Bellis perennis", symbol: "camera.macro"),
        TaxonSearchExample(name: String(localized: "Red fox"), scientificName: "Vulpes vulpes", symbol: "pawprint"),
        TaxonSearchExample(name: String(localized: "Western honey bee"), scientificName: "Apis mellifera", symbol: "ladybug")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 12) {
                    Image(systemName: "character.book.closed.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)

                    Text("Names in every language")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)

                    Text("Search once. See the common name in all your configured languages.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your languages")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(languages) { language in
                                    Label(
                                        TaxonLanguagePresentation.displayName(for: language),
                                        systemImage: "character"
                                    )
                                    .font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(.tint.opacity(0.12), in: Capsule())
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Try a taxon")
                        .font(.headline)

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 145), spacing: 10)],
                        spacing: 10
                    ) {
                        ForEach(examples) { example in
                            Button {
                                Task { await resolve(example.scientificName) }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: example.symbol)
                                        .frame(width: 24)
                                        .foregroundStyle(.tint)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(example.name)
                                            .font(.subheadline.weight(.semibold))
                                        Text(example.scientificName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                                .padding(.horizontal, 12)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityHint("Searches for \(example.scientificName)")
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 20)
        }
    }
}

private struct TaxonSearchExample: Identifiable {
    let name: String
    let scientificName: String
    let symbol: String

    var id: String { scientificName }
}

/// Must be a descendant of `.searchable` so SwiftUI supplies its active dismiss action.
private struct SearchDismissObserver: View {
    @Environment(\.dismissSearch) private var dismissSearch
    let shouldDismiss: Bool

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: shouldDismiss, initial: true) { _, shouldDismiss in
                if shouldDismiss {
                    dismissSearch()
                }
            }
            .accessibilityHidden(true)
    }
}

private struct CandidateList: View {
    let candidates: [TaxonCandidate]
    let select: (TaxonCandidate) -> Void

    var body: some View {
        List {
            ForEach(CandidateHierarchy.sections(for: candidates)) { section in
                Section {
                    ForEach(section.candidates) { candidate in
                        Button {
                            select(candidate)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                if section.kind == .infraspecific {
                                    Image(systemName: "arrow.turn.down.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                        .accessibilityHidden(true)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(candidate.taxon.scientificName.value)
                                        .font(.headline)
                                    if let matchedName = candidate.matchedName,
                                       TaxonSearchQuery.normalize(matchedName)
                                        != TaxonSearchQuery.normalize(candidate.taxon.scientificName.value) {
                                        Text(matchedName)
                                            .foregroundStyle(.secondary)
                                    }
                                    if let rank = candidate.taxon.rank {
                                        Text(localizedRankName(rank))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .accessibilityLabel(candidate.taxon.scientificName.value)
                    }
                } header: {
                    Text(section.title)
                }
            }
        }
    }
}

private extension CandidateHierarchy.Section {
    var title: LocalizedStringKey {
        switch kind {
        case .species: "Species"
        case .infraspecific:
            if candidates.allSatisfy({
                $0.taxon.rank?.name.caseInsensitiveCompare("subspecies") == .orderedSame
            }) {
                "Subspecies"
            } else {
                "Below species"
            }
        case .other: "Other taxa"
        }
    }
}

private struct TaxonResultView: View {
    let taxon: Taxon
    let configuration: OutputLanguageConfiguration
    let preferredWikipediaLanguage: TaxonLanguage?
    let startNewSearch: () -> Void

    var body: some View {
        List {
            Section("Names in your languages") {
                ForEach(configuration.displayRows(for: taxon)) { row in
                    NameRow(
                        row: row,
                        alternativeNames: alternativeNames(for: row)
                    )
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
        .listSectionSpacing(.compact)
        .environment(\.defaultMinListRowHeight, 40)
        .contentMargins(.top, 4, for: .scrollContent)
        .navigationTitle(taxon.scientificName.value)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Search", systemImage: "chevron.backward", action: startNewSearch)
            }
        }
    }

    private func alternativeNames(for row: TaxonDisplayRow) -> [LocalizedTaxonName] {
        guard case let .localized(language, _) = row else { return [] }
        return taxon.alternativeNames(for: language)
    }
}

private func localizedRankName(_ rank: TaxonomicRank) -> String {
    String(localized: String.LocalizationValue(rank.name.capitalized))
}

private struct NameRow: View {
    let row: TaxonDisplayRow
    let alternativeNames: [LocalizedTaxonName]

    private var label: String {
        switch row {
        case .scientific: return "Scientific"
        case let .localized(language, _):
            return TaxonLanguagePresentation.displayName(for: language)
        }
    }

    private var name: String? {
        switch row {
        case let .scientific(scientificName): return scientificName.value
        case let .localized(_, localizedName): return localizedName?.displayValue
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(
                    minWidth: 88,
                    idealWidth: 104,
                    maxWidth: 125,
                    alignment: .leading
                )
            if let name {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(name)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)

                    if !alternativeNames.isEmpty {
                        Text(
                            alternativeNames
                                .map(\.displayValue)
                                .joined(separator: ", ")
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.trailing)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .layoutPriority(1)
            } else {
                Text("Not available")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
        .accessibilityElement(children: .combine)
    }

}

private struct AppSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: SearchModel
    let catalogueOfLife: CatalogueOfLifeProvider
    @State private var languageCode = ""
    @FocusState private var isLanguageFieldFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.configuredLanguages) { language in
                        Text(TaxonLanguagePresentation.displayName(for: language))
                    }
                    .onDelete(perform: model.removeLanguages)
                    .onMove(perform: model.moveLanguages)

                    HStack {
                        TextField("Language code", text: $languageCode)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($isLanguageFieldFocused)
                            .submitLabel(.done)
                            .onSubmit { addLanguage() }
                        Button("Add") {
                            addLanguage()
                        }
                        .disabled(
                            TaxonLanguagePresentation.language(from: languageCode)
                                .map(model.configuredLanguages.contains) != false
                        )
                    }
                } header: {
                    Text("Languages")
                } footer: {
                    Text("Search in any of these languages. Results include every language in this order.")
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
                            Text(TaxonLanguagePresentation.displayName(for: language))
                                .tag(Optional(language))
                        }
                    }
                }

                Section("About") {
                    NavigationLink {
                        DataSourcesView(catalogueOfLife: catalogueOfLife)
                    } label: {
                        Label("Data sources", systemImage: "books.vertical")
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func addLanguage() {
        Task {
            if await model.addLanguage(input: languageCode) {
                languageCode = ""
            }
        }
    }
}
