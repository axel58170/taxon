import Foundation
import Testing
import UniformTypeIdentifiers

@MainActor
struct ShareTextLoaderTests {
    @Test("Loads NSString plain text")
    func loadsNSString() async throws {
        let provider = NSItemProvider(
            item: "Strix aluco" as NSString,
            typeIdentifier: UTType.plainText.identifier
        )

        let text = try await ShareTextLoader.loadText(from: [extensionItem(provider)])

        #expect(text == "Strix aluco")
    }

    @Test("Loads UTF-8 data")
    func loadsUTF8Data() async throws {
        let provider = NSItemProvider(
            item: Data("Strix aluco".utf8) as NSData,
            typeIdentifier: UTType.utf8PlainText.identifier
        )

        let text = try await ShareTextLoader.loadText(from: [extensionItem(provider)])

        #expect(text == "Strix aluco")
    }

    @Test("Falls back after an unreadable provider")
    func fallsBackToNextProvider() async throws {
        let unreadable = NSItemProvider(
            item: NSDate(),
            typeIdentifier: UTType.utf8PlainText.identifier
        )
        let readable = NSItemProvider(
            item: "Strix aluco" as NSString,
            typeIdentifier: UTType.plainText.identifier
        )

        let text = try await ShareTextLoader.loadText(
            from: [extensionItem(unreadable), extensionItem(readable)]
        )

        #expect(text == "Strix aluco")
    }

    private func extensionItem(_ provider: NSItemProvider) -> NSExtensionItem {
        let item = NSExtensionItem()
        item.attachments = [provider]
        return item
    }
}
