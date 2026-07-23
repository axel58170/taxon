import SwiftUI
import AppIntents
import TaxonSettings
import WikidataProvider

@main
struct TaxonApp: App {
    @State private var searchModel: SearchModel

    init() {
        let resolver = WikidataProvider()
        let settingsStore = SharedOutputSettingsStore.production()
        let intentService = TaxonIntentService(resolver: resolver, settingsStore: settingsStore)
        _searchModel = State(initialValue: SearchModel(resolver: resolver, settingsStore: settingsStore))
        AppDependencyManager.shared.add(dependency: intentService)
    }

    var body: some Scene {
        WindowGroup {
            TaxonSearchView(model: searchModel)
        }
    }
}
