import Foundation
import TaxonDomain

enum TaxonLanguagePresentation {
    static func language(from input: String, locale: Locale = .current) -> TaxonLanguage? {
        if let language = TaxonLanguage(rawValue: input) {
            return language
        }

        let normalizedInput = normalizedName(input, locale: locale)
        guard !normalizedInput.isEmpty else { return nil }

        return Locale.LanguageCode.isoLanguageCodes.lazy.compactMap { code in
            guard
                let displayName = locale.localizedString(forLanguageCode: code.identifier),
                normalizedName(displayName, locale: locale) == normalizedInput
            else {
                return nil
            }
            return TaxonLanguage(rawValue: code.identifier)
        }.first
    }

    static func displayName(for language: TaxonLanguage, locale: Locale = .current) -> String {
        let name = locale.localizedString(forLanguageCode: language.baseLanguageCode)
            ?? language.rawValue
        guard let first = name.first else { return name }
        return String(first).uppercased(with: locale) + name.dropFirst()
    }

    private static func normalizedName(_ value: String, locale: Locale) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
    }
}
