# Taxon

Taxon is a lightweight iOS utility for resolving biological taxa—including animals, plants, fungi, and other taxonomic groups—and presenting their common names in a user-defined order of languages. Catalogue of Life is the primary discovery and vernacular-name source, with Wikidata providing canonical identity verification and Wikipedia links.

## Status

The initial working increment is implemented: SwiftUI search and result presentation, configurable ordered languages, a reusable domain package, fixture-tested Catalogue of Life and Wikidata resolution, App Intents, a plain-text Share Extension, and dynamic Catalogue of Life release attribution in Settings. Durable caching and the remaining v1 acceptance criteria are intentionally deferred.

The app and Share Extension are localized in English, French, Dutch, and Italian. The interface language follows iOS and is independent of the ordered languages configured for taxon lookup and results.

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
    │   └── App Group-backed language configuration
    ├── CatalogueOfLifeProvider
    │   ├── scientific and vernacular discovery
    │   └── Wikidata-verified resolver composition
    └── WikidataProvider
        ├── Action API and SPARQL transport
        ├── response DTOs and mapping
        └── Wikidata-specific identifiers and semantics
```

`TaxonDomain` is intentionally provider-independent and Foundation-only. A taxon’s canonical identity comprises a validated Wikidata Q-ID and its scientific name. Catalogue of Life is the primary discovery and vernacular-name source; Wikidata verifies the linked Q-ID, supplies the authoritative `P225` scientific name, and hydrates Wikipedia sitelinks. Source-specific identifiers from Catalogue of Life, eBird, GBIF, IOC, or other providers remain external enrichment rather than core identity.

The application and App Intents depend on a resolver protocol, so tests and previews can use deterministic fixtures. `WikidataProvider` is the only module that knows Wikidata HTTP payload shapes and properties. `CatalogueOfLifeProvider` searches both scientific and vernacular indexes and accepts results only when the COL scientific name and linked Wikidata identifier agree with Wikidata hydration; Catalogue of Life identifiers and DTOs remain private to that module.

## Lookup approach

1. Normalize text locally for comparison while retaining the original input for the request.
2. Search the current Catalogue of Life Extended Release's scientific-name and dataset-wide vernacular indexes concurrently.
3. Keep exact normalized matches, hydrate only their bounded COL taxon IDs, and require an accepted usage with a linked Wikidata Q-ID.
4. Hydrate that Q-ID through Wikidata, verifying that `P225` agrees with the COL scientific name and retrieving taxonomic rank, labels, aliases, and Wikipedia sitelinks.
5. Preserve all exact common-name matches as explicit candidates rather than silently guessing.
6. If COL has no verified match or is unavailable, use the existing bounded Wikidata text-search, taxon-gating, and hydration path as a compatibility fallback.

Scientific names always come from `P225` after identity verification. Wikipedia links always come from real Wikidata sitelinks, using preferred Wikipedia language, configured languages, then any available article as fallback. Cancellation propagates, but a Catalogue of Life transport or decoding failure does not prevent the Wikidata compatibility path from running.

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

The main app uses Catalogue of Life discovery with Wikidata identity verification and fallback. Package and app tests remain deterministic: they use constructed JSON fixtures and the in-memory mock resolver, never live services.

The Wikipedia-opening intent uses `OpenURLIntent`, which is available on iOS 18 and later. The rest of the app and intent surface retains the iOS 17 deployment target.

The app, App Intents, and Share Extension share language settings through the `group.com.axelgraff.taxon` App Group. Device builds require an Apple Developer account and provisioning profiles for both `com.axelgraff.taxon` and `com.axelgraff.taxon.share` that include this App Group.

### Testing App Intents

Install and launch Taxon once, then open Shortcuts and choose **New Shortcut → Add Action → Apps → Taxon**. Taxon exposes **Resolve Taxon**, **Get Taxon Name**, and **Get Configured Taxon Names** on iOS 17 and later. The separately embedded Share Extension provides Taxon’s Share Sheet entry.

### Testing the Share Extension

Install and launch Taxon once, configure the languages, then select or share plain text from another app. Choose **Taxon** in the Share Sheet. The extension resolves the text and displays every configured language plus the scientific name, preserving the configured order. Individual available names and the complete available result can be copied.

## Development conventions

Repository-specific rules, module boundaries, provider safeguards, and testing expectations are in [AGENTS.md](AGENTS.md). Read it before changing application code.

## Scope guardrails

The first release deliberately excludes Merlin integration, image recognition, sound, maps, observation recording, and downloadable taxonomic databases. Those capabilities must not be added incidentally while establishing the lookup foundation.
