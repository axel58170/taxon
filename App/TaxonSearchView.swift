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
                        preferredWikipediaLanguage: model.preferredWikipediaLanguage
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
                    Button("Languages", systemImage: "globe") {
                        showingSettings = true
                    }
                    .accessibilityLabel("Configure languages")
                }
            }
            .sheet(isPresented: $showingSettings) {
                LanguageSettings(model: model)
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
                                            .italic()
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
            Section("Names in your languages") {
                ForEach(configuration.displayRows(for: taxon)) { row in
                    NameRow(row: row)
                }
            }

            if let rank = taxon.rank {
                Section("Taxon") {
                    HStack(spacing: 12) {
                        Label(rank.name.capitalized, systemImage: "point.3.connected.trianglepath.dotted")
                        Spacer(minLength: 8)
                        Text(taxon.wikidataID.rawValue)
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
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
    }
}

private struct NameRow: View {
    let row: TaxonDisplayRow
    @State private var copied = false

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
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            if let name {
                Text(name)
                    .multilineTextAlignment(.trailing)
                    .italic(isScientific)
                Button {
                    copy(name)
                } label: {
                    Image(systemName: copied ? "checkmark.circle.fill" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(copied ? Color.green : Color.accentColor)
                .accessibilityLabel(
                    copied
                        ? String(localized: "Copied")
                        : String(localized: "Copy \(label) name")
                )
                .sensoryFeedback(.success, trigger: copied)
            } else {
                Text("Not available")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(label) name not available")
            }
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }

    private var isScientific: Bool {
        if case .scientific = row { return true }
        return false
    }

    private func copy(_ name: String) {
        UIPasteboard.general.string = name
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}

private struct LanguageSettings: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: SearchModel
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
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Languages")
            .task { isLanguageFieldFocused = true }
            .toolbar {
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
