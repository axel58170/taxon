import Foundation
import TaxonDomain

struct ShareResultRow: Hashable, Identifiable, Sendable {
    let id: String
    let label: String
    let value: String?
    let isScientific: Bool
}

enum ShareResultFormatter {
    static func rows(for taxon: Taxon, configuration: OutputLanguageConfiguration) -> [ShareResultRow] {
        configuration.displayRows(for: taxon).map { row in
            switch row {
            case let .scientific(name):
                return ShareResultRow(id: "scientific", label: "Scientific", value: name.value, isScientific: true)
            case let .localized(language, name):
                return ShareResultRow(
                    id: "localized-\(language.rawValue)",
                    label: language.rawValue,
                    value: name?.displayValue,
                    isScientific: false
                )
            }
        }
    }

    static func formattedAvailableRows(_ rows: [ShareResultRow]) -> String {
        rows.compactMap { row in
            row.value.map { "\(row.label): \($0)" }
        }.joined(separator: "\n")
    }
}
