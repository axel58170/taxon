import Foundation
import Testing
import TaxonDomain
@testable import TaxonSettings

struct SharedOutputSettingsStoreTests {
    @Test("Missing settings use the expected output defaults")
    func loadsDefaults() {
        withIsolatedDefaults { _, store in
            let snapshot = store.load()

            #expect(snapshot.languages.map(\.rawValue) == ["en", "fr", "nl"])
            #expect(snapshot.scientificNamePosition == .last)
            #expect(snapshot.preferredWikipediaLanguage?.rawValue == "en")
        }
    }

    @Test("Language order, scientific position, and Wikipedia language round trip")
    func roundTripsSnapshot() {
        withIsolatedDefaults { _, store in
            let expected = OutputSettingsSnapshot(
                languages: ["nl", "de", "fr"].compactMap(TaxonLanguage.init(rawValue:)),
                scientificNamePosition: .first,
                preferredWikipediaLanguage: TaxonLanguage(rawValue: "de")
            )

            store.save(expected)

            #expect(store.load() == expected)
        }
    }

    @Test("Duplicate languages are removed without changing first-occurrence order")
    func removesDuplicateLanguages() {
        let snapshot = OutputSettingsSnapshot(
            languages: ["nl", "fr", "nl"].compactMap(TaxonLanguage.init(rawValue:)),
            scientificNamePosition: .last,
            preferredWikipediaLanguage: nil
        )

        #expect(snapshot.languages.map(\.rawValue) == ["nl", "fr"])
    }

    @Test("Corrupt storage falls back to defaults")
    func corruptDataFallsBack() {
        withIsolatedDefaults { defaults, store in
            defaults.set(Data("not a property list".utf8), forKey: SharedOutputSettingsStore.defaultStorageKey)

            #expect(store.load() == .default)
        }
    }

    @Test("Invalid persisted values fall back to defaults")
    func invalidValuesFallBack() throws {
        try withIsolatedDefaults { defaults, store in
            let invalid: [String: Any] = [
                "schemaVersion": 1,
                "languages": ["en", "   "],
                "scientificNamePosition": "middle",
                "preferredWikipediaLanguage": "en"
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: invalid, format: .binary, options: 0)
            defaults.set(data, forKey: SharedOutputSettingsStore.defaultStorageKey)

            #expect(store.load() == .default)
        }
    }

    private func withIsolatedDefaults(
        _ operation: (UserDefaults, SharedOutputSettingsStore) throws -> Void
    ) rethrows {
        let suiteName = "TaxonSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try operation(defaults, SharedOutputSettingsStore(userDefaults: defaults))
    }
}
