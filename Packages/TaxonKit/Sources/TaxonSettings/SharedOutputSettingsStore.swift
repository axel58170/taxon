import Foundation
import TaxonDomain

/// The user-controlled naming configuration shared by the app and its system integrations.
public struct OutputSettingsSnapshot: Codable, Hashable, Sendable {
    public let languages: [TaxonLanguage]
    public let scientificNamePosition: ScientificNamePosition
    public let preferredWikipediaLanguage: TaxonLanguage?

    public init(
        languages: [TaxonLanguage],
        scientificNamePosition: ScientificNamePosition,
        preferredWikipediaLanguage: TaxonLanguage?
    ) {
        var seen = Set<TaxonLanguage>()
        self.languages = languages.filter { seen.insert($0).inserted }
        self.scientificNamePosition = scientificNamePosition
        self.preferredWikipediaLanguage = preferredWikipediaLanguage
    }

    public static let `default` = OutputSettingsSnapshot(
        languages: ["en", "fr", "nl"].compactMap(TaxonLanguage.init(rawValue:)),
        scientificNamePosition: .last,
        preferredWikipediaLanguage: TaxonLanguage(rawValue: "en")
    )
}

/// Synchronous `UserDefaults` persistence suitable for use by the app and extension processes.
public struct SharedOutputSettingsStore: @unchecked Sendable {
    public static let appGroupSuiteName = "group.com.taxon.app"
    public static let defaultStorageKey = "output-settings-v1"

    private let userDefaults: UserDefaults
    private let storageKey: String

    public init(
        userDefaults: UserDefaults,
        storageKey: String = SharedOutputSettingsStore.defaultStorageKey
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
    }

    /// Creates the shared production store. Standard defaults are a defensive fallback for invalid environments.
    public static func production(
        appGroupSuiteName: String = SharedOutputSettingsStore.appGroupSuiteName
    ) -> SharedOutputSettingsStore {
        SharedOutputSettingsStore(
            userDefaults: UserDefaults(suiteName: appGroupSuiteName) ?? .standard
        )
    }

    public func load() -> OutputSettingsSnapshot {
        guard
            let data = userDefaults.data(forKey: storageKey),
            let persisted = try? PropertyListDecoder().decode(PersistedSnapshot.self, from: data),
            let snapshot = persisted.validatedSnapshot
        else {
            return .default
        }
        return snapshot
    }

    public func save(_ snapshot: OutputSettingsSnapshot) {
        let persisted = PersistedSnapshot(snapshot: snapshot)
        guard let data = try? PropertyListEncoder().encode(persisted) else { return }
        userDefaults.set(data, forKey: storageKey)
    }
}

private struct PersistedSnapshot: Codable {
    let schemaVersion: Int
    let languages: [String]
    let scientificNamePosition: String
    let preferredWikipediaLanguage: String?

    init(snapshot: OutputSettingsSnapshot) {
        schemaVersion = 1
        languages = snapshot.languages.map(\.rawValue)
        scientificNamePosition = snapshot.scientificNamePosition.rawValue
        preferredWikipediaLanguage = snapshot.preferredWikipediaLanguage?.rawValue
    }

    var validatedSnapshot: OutputSettingsSnapshot? {
        guard schemaVersion == 1 else { return nil }

        let decodedLanguages = languages.compactMap(TaxonLanguage.init(rawValue:))
        guard decodedLanguages.count == languages.count else { return nil }
        guard let position = ScientificNamePosition(rawValue: scientificNamePosition) else { return nil }

        let preferredLanguage: TaxonLanguage?
        if let preferredWikipediaLanguage {
            guard let decoded = TaxonLanguage(rawValue: preferredWikipediaLanguage) else { return nil }
            preferredLanguage = decoded
        } else {
            preferredLanguage = nil
        }

        return OutputSettingsSnapshot(
            languages: decodedLanguages,
            scientificNamePosition: position,
            preferredWikipediaLanguage: preferredLanguage
        )
    }
}
