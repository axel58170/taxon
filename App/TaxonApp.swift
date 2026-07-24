import SwiftUI
import AppIntents
import CatalogueOfLifeProvider
import TaxonSettings
import WikidataProvider

@main
struct TaxonApp: App {
    @State private var searchModel: SearchModel
    private let catalogueOfLife: CatalogueOfLifeProvider

    init() {
        let catalogueOfLife = CatalogueOfLifeProvider()
        let resolver = CatalogueOfLifePrimaryResolver(
            secondary: WikidataProvider(),
            catalogueOfLife: catalogueOfLife
        )
        let settingsStore = SharedOutputSettingsStore.production()
        let intentService = TaxonIntentService(resolver: resolver, settingsStore: settingsStore)
        _searchModel = State(initialValue: SearchModel(resolver: resolver, settingsStore: settingsStore))
        self.catalogueOfLife = catalogueOfLife
        AppDependencyManager.shared.add(dependency: intentService)
    }

    var body: some Scene {
        WindowGroup {
            TaxonSearchView(
                model: searchModel,
                catalogueOfLife: catalogueOfLife
            )
        }
    }
}
