import Foundation
import UniformTypeIdentifiers

@MainActor
enum ShareTextLoader {
    enum LoadingError: Error {
        case noReadableText
    }

    static func loadText(from items: [NSExtensionItem]) async throws -> String {
        let providers = items.flatMap { $0.attachments ?? [] }

        for provider in providers {
            for typeIdentifier in textTypeIdentifiers(for: provider) {
                do {
                    let item = try await provider.loadItem(
                        forTypeIdentifier: typeIdentifier,
                        options: nil
                    )
                    if let text = decode(item) {
                        return text
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    continue
                }
            }
        }

        throw LoadingError.noReadableText
    }

    private static func textTypeIdentifiers(for provider: NSItemProvider) -> [String] {
        provider.registeredTypeIdentifiers
            .filter { UTType($0)?.conforms(to: .text) == true }
            .sorted { left, right in
                priority(of: left) < priority(of: right)
            }
    }

    private static func priority(of typeIdentifier: String) -> Int {
        switch typeIdentifier {
        case UTType.utf8PlainText.identifier: 0
        case UTType.plainText.identifier: 1
        default: 2
        }
    }

    private static func decode(_ item: NSSecureCoding?) -> String? {
        switch item {
        case let value as String:
            return value
        case let value as NSString:
            return value as String
        case let value as NSAttributedString:
            return value.string
        case let data as Data:
            return String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .utf16)
        case let url as URL where url.isFileURL:
            return try? String(contentsOf: url, encoding: .utf8)
        default:
            return nil
        }
    }
}
