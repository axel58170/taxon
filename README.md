# Taxon

Taxon is a lightweight iOS utility for resolving a biological taxon and presenting its common names in a user-defined order of languages. Its initial data source is Wikidata; its initial use case is birds, without making birds a constraint of the core model.

## Status

The initial working increment is implemented: SwiftUI search and result presentation, configurable ordered output languages, a reusable domain package, fixture-tested Wikidata resolution, App Intents, and a plain-text Share Extension. Durable caching and the remaining v1 acceptance criteria are intentionally deferred.

## Architecture

```text
Taxon (iOS application)
├── SwiftUI search, result, and settings surfaces
├── App Intents adapters and composition root
└── TaxonKit (Swift package)
    ├── TaxonDomain
    │   ├── canonical taxon and localized-name values
    │   ├── query normalization and resolution rules
    │   └── provider protocols
    ├── TaxonSettings
    │   └── App Group-backed output-language configuration
    └── WikidataProvider
        ├── Action API and SPARQL transport
        ├── response DTOs and mapping
        └── Wikidata-specific identifiers and semantics
```

`TaxonDomain` is intentionally provider-independent and Foundation-only. A taxon’s canonical identity comprises a validated Wikidata Q-ID and its scientific name. Wikidata is the initial authority for that Q-ID, while source-specific identifiers from eBird, GBIF, IOC, or other providers remain external enrichment rather than core identity.

The application and App Intents depend on a resolver protocol, so tests and previews can use deterministic fixtures. `WikidataProvider` is the only module that knows Wikidata HTTP payload shapes and properties.

## Wikidata lookup approach

1. Normalize text locally for comparison while retaining the original input for the request.
2. Discover a bounded candidate set with Wikidata’s `wbsearchentities` API.
3. Verify candidates are taxa with a bounded Wikidata Query Service request.
4. Hydrate eligible Q-IDs through `wbgetentities`, retrieving `P225` (scientific taxon name), `P105` (taxonomic rank), labels, aliases, and Wikipedia sitelinks.
5. Rank exact scientific-name and configured-language matches ahead of less precise matches. Ambiguous results remain candidates for the user to choose.

Scientific names always come from `P225` when available. Wikipedia links always come from real Wikidata sitelinks, using preferred Wikipedia language, configured languages, then any available article as fallback.

## Build

Prerequisites:

- Xcode 26 or later with an iOS simulator runtime.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) for regenerating the project from `project.yml`.

Generate and open the project:

```sh
xcodegen generate
open Taxon.xcodeproj
```

Build and test from the command line:

```sh
xcodebuild -project Taxon.xcodeproj -scheme Taxon -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
xcodebuild -project Taxon.xcodeproj -scheme Taxon -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
swift test --package-path Packages/TaxonKit
```

`Taxon.xcodeproj` is generated from `project.yml` and committed so the app can also be opened immediately. Regenerate it after changing targets, package products, or build settings.

The main app uses the live Wikidata provider. Package and app tests remain deterministic: they use constructed JSON fixtures and the in-memory mock resolver, never the live service.

The Wikipedia-opening intent uses `OpenURLIntent`, which is available on iOS 18 and later. The rest of the app and intent surface retains the iOS 17 deployment target.

The app, App Intents, and Share Extension share language settings through the `group.com.axelgraff.taxon` App Group. Device builds require an Apple Developer account and provisioning profiles for both `com.axelgraff.taxon` and `com.axelgraff.taxon.share` that include this App Group.

### Testing App Intents

Install and launch Taxon once, then open Shortcuts and choose **New Shortcut → Add Action → Apps → Taxon**. Taxon exposes **Resolve Taxon**, **Get Taxon Name**, and **Get Configured Taxon Names** on iOS 17 and later. The separately embedded Share Extension provides Taxon’s Share Sheet entry.

### Testing the Share Extension

Install and launch Taxon once, configure the output languages, then select or share plain text from another app. Choose **Taxon** in the Share Sheet. The extension resolves the text and displays every configured language plus the scientific name, preserving the configured order. Individual available names and the complete available result can be copied.

## Development conventions

Repository-specific rules, module boundaries, provider safeguards, and testing expectations are in [AGENTS.md](AGENTS.md). Read it before changing application code.

## Scope guardrails

The first release deliberately excludes Merlin integration, image recognition, sound, maps, observation recording, and downloadable taxonomic databases. Those capabilities must not be added incidentally while establishing the lookup foundation.
