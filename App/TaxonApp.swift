import SwiftUI
import AppIntents
import WikidataProvider

@main
struct TaxonApp: App {
    @State private var searchModel: SearchModel

    init() {
        let resolver = WikidataProvider()
        let intentService = TaxonIntentService(resolver: resolver)
        _searchModel = State(initialValue: SearchModel(resolver: resolver))
        AppDependencyManager.shared.add(dependency: intentService)
    }

    var body: some Scene {
        WindowGroup {
            TaxonSearchView(model: searchModel)
        }
    }
}
