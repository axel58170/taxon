import SwiftUI
import TaxonSettings
import UIKit
import WikidataProvider

@MainActor
final class ShareViewController: UIViewController {
    private let model = ShareLookupModel(
        resolver: WikidataProvider(),
        settings: SharedOutputSettingsStore.production().load()
    )
    private var loadTask: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()
        installSwiftUI()
        loadTask = Task { [weak self] in await self?.loadSharedText() }
    }

    deinit {
        loadTask?.cancel()
    }

    private func installSwiftUI() {
        let controller = UIHostingController(rootView: ShareView(model: model) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        addChild(controller)
        view.addSubview(controller.view)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: view.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        controller.didMove(toParent: self)
    }

    private func loadSharedText() async {
        do {
            let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
            let text = try await ShareTextLoader.loadText(from: items)
            guard !Task.isCancelled else { return }
            await model.resolve(text)
        } catch is CancellationError {
            // Extension dismissal cancels the task.
        } catch {
            model.failToLoadInput()
        }
    }
}
