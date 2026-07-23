import SwiftUI
import WikidataProvider

@main
struct TaxonApp: App {
    @State private var searchModel = SearchModel(resolver: WikidataProvider())

    var body: some Scene {
        WindowGroup {
            TaxonSearchView(model: searchModel)
        }
    }
}
