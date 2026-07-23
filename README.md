# Taxon

Taxon is a lightweight iOS utility for resolving a biological taxon and presenting its common names in a user-defined order of languages. Its initial data source is Wikidata; its initial use case is birds, without making birds a constraint of the core model.

## Status

The repository is being scaffolded from the product requirements in [PRD.md](PRD.md). The first working increment will provide SwiftUI search, fixture-backed Wikidata resolution, configurable output languages, and App Intents. Share Sheet support, durable caching, and the broader v1 acceptance criteria follow as separate increments.

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

Once the Swift entry point and package manifest have been added, generate and open the project:

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

The repository currently contains only the generator configuration and directory layout; it becomes buildable when the next scaffold commit adds the Swift entry point and package manifest.

## Development conventions

Repository-specific rules, module boundaries, provider safeguards, and testing expectations are in [AGENTS.md](AGENTS.md). Read it before changing application code.

## Scope guardrails

The first release deliberately excludes Merlin integration, image recognition, sound, maps, observation recording, and downloadable taxonomic databases. Those capabilities must not be added incidentally while establishing the lookup foundation.
