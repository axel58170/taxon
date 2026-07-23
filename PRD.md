# Taxon

## Product Requirements Document

**Status:** Initial product definition  
**Primary platform:** iOS  
**Initial domain:** Birds  
**Long-term domain:** Biological taxa across kingdoms

## 1. Product summary

Taxon is a lightweight iOS utility for resolving a species name in one language and displaying the corresponding common names in the user’s configured languages, together with the canonical scientific name.

The primary workflow is system-wide. A user selects a name such as `wespendief` in any app, invokes Taxon through the Share Sheet or an App Intent, and receives names such as:

| Language | Name |
| --- | --- |
| English | European Honey-buzzard |
| French | Bondrée apivore |
| Dutch | Wespendief |
| Scientific | *Pernis apivorus* |

The scientific taxon is the stable identity. Common names are localized representations of that taxon rather than independent dictionary entries.

Birds are the first use case because the initial need comes from multilingual bird identification and field-guide workflows. The architecture must nevertheless avoid bird-specific assumptions so that plants, fungi, insects, mammals, and other taxa can be supported later.

## 2. Problem

Species names are difficult to translate with a conventional dictionary because:

- Common names are not literal translations.
- A species can have regional and historical names.
- The same common name may refer to different taxa.
- Taxonomies and accepted scientific names change.
- Field-guide apps often support only a subset of the languages a user needs.
- Copying a name into Wikipedia or several specialist sites interrupts the user’s current task.

A useful solution must resolve the input to a taxonomic entity first and only then retrieve the appropriate localized names.

## 3. Goals

Version 1 must let a user:

1. Enter or share a common or scientific species name.
2. Resolve the input to a Wikidata taxon.
3. View the scientific name and common names in a configurable, ordered list of languages.
4. Copy an individual name or all displayed names.
5. Open a relevant Wikipedia article.
6. Invoke the same lookup through App Intents and Shortcuts.
7. Reuse recent results without another network request.

The normal lookup should require no more than one deliberate action after selecting text and should usually finish within one second on a working network connection.

## 4. Non-goals for version 1

Version 1 will not provide:

- Species identification from photographs or sound.
- Observation recording.
- Distribution maps.
- Audio recordings.
- A proprietary taxonomy.
- Full offline taxonomic databases.
- Automatic navigation to a species page inside Merlin Bird ID.
- AI-generated translations or taxonomic assertions.

These exclusions keep the first implementation focused on reliable entity resolution and multilingual naming.

## 5. Product principles

### 5.1 Taxon-first identity

The app must resolve text to a taxonomic entity before presenting translations. The canonical application identifier is initially the Wikidata Q-ID. The accepted scientific name must also be stored because it is portable across external services.

### 5.2 Configurable languages

The language list must not be hard-coded. Users can add, remove, and reorder languages. Scientific naming is shown as a separate configurable row rather than being treated as a normal locale.

### 5.3 Source transparency

Names must retain source information internally. The UI should make it possible to identify the source when needed, particularly where sources disagree or regional alternatives exist.

### 5.4 General taxonomic model

Core models, services, caching, and intents must not assume that every result is a bird or species-rank taxon.

### 5.5 Minimal interruption

The primary experience is a small result surface, not a full research application. It should be fast to invoke, easy to dismiss, and useful without leaving the current app where iOS permits this.

## 6. Primary user stories

### 6.1 Translate selected text

As a user reading an article, message, or field guide, I select `Bondrée apivore`, invoke Taxon, and immediately see the configured names and *Pernis apivorus*.

### 6.2 Search inside the app

As a user who knows part of a name, I type it into Taxon, review possible matches, and select the intended taxon.

### 6.3 Copy a localized name

As a user preparing a message in French, I resolve `wespendief` and copy `Bondrée apivore` without copying the other names.

### 6.4 Use a Shortcut

As a Shortcuts user, I pass text to the Resolve Taxon action and use its structured result in a later action such as Copy Taxon Name or Open Wikipedia.

### 6.5 Prepare a field-guide lookup

As a Merlin Bird ID user, I resolve a bird name and copy the common name in the language I use in Merlin. Direct species navigation is a future integration because Merlin must expose a supported deep link or App Intent.

## 7. Functional requirements

### 7.1 Search input

The app must accept:

- A common name.
- A scientific name.
- Text received from the Share Sheet.
- Text supplied to an App Intent.

Search must be case-insensitive and should be accent-insensitive where that does not materially change meaning.

For version 1, exact and prefix matches are required. Fuzzy matching is optional and must not silently select a taxon when confidence is low.

### 7.2 Entity resolution

The lookup service must:

1. Search Wikidata for candidate entities.
2. Prefer entities that are instances or subclasses of taxon.
3. Retrieve the Wikidata Q-ID, scientific name, taxonomic rank, and requested localized labels.
4. Return multiple candidates when the input is ambiguous.
5. Avoid presenting a non-taxonomic entity as a successful result.

Where Wikidata exposes a taxon name property distinct from the localized item label, the taxon name property is authoritative for the scientific name.

### 7.3 Result display

A resolved result must display:

- Scientific name.
- Taxonomic rank when known.
- Common name for every configured language where available.
- A clear missing-value state where a requested language has no name.
- Copy controls for each displayed name.
- A control to copy the complete formatted result.
- A control to open Wikipedia.

The configured order must be preserved.

### 7.4 Ambiguous results

When several taxa plausibly match the input, the app must show a candidate list containing enough context to choose safely. Candidate rows should include the scientific name, available common name, and rank. The app must not guess merely to remove a tap.

### 7.5 Language settings

The user must be able to:

- Add any locale supported by the naming source.
- Remove a locale.
- Reorder locales.
- Choose whether the scientific name appears first or last.
- Select a preferred Wikipedia language.

Initial defaults may be derived from the user’s preferred system languages, but the app must not assume English, French, and Dutch are universally appropriate.

### 7.6 Share Sheet

A Share extension must accept plain text. When invoked with selected text, it should resolve the text and show a compact result.

The extension should provide at least these actions:

- Copy a selected localized name.
- Copy all configured names.
- Open the result in the main app.

The implementation must account for Share extension memory and execution constraints. Shared domain logic should live in a reusable package or framework rather than being duplicated between targets.

### 7.7 App Intents

Version 1 must expose the following intents.

#### Resolve Taxon

**Input:** Text  
**Output:** `TaxonEntity`

The intent resolves common or scientific names. When resolution is ambiguous, Shortcuts should be able to ask the user to choose a candidate.

#### Get Taxon Name

**Input:** `TaxonEntity`, language  
**Output:** Text

The intent returns the name for a requested language or a clear no-result state.

#### Get Configured Taxon Names

**Input:** `TaxonEntity`  
**Output:** A formatted text result containing the user’s configured languages and scientific name.

#### Open Taxon in Wikipedia

**Input:** `TaxonEntity`, optional language  
**Output:** Opens the best available Wikipedia page.

`TaxonEntity` should conform to `AppEntity` and expose a useful display representation based on the localized and scientific names.

### 7.8 Wikipedia links

The app should derive language-specific Wikipedia pages from Wikidata sitelinks rather than constructing article titles from labels. If the preferred language has no article, the app should fall back through the user’s configured languages and finally to any available article.

### 7.9 Cache

Successful lookups must be cached locally. The cache should store:

- Q-ID.
- Scientific name.
- Rank.
- Retrieved localized names.
- Relevant sitelinks.
- Retrieval timestamp.

Cached results should appear immediately. The app may refresh stale data in the background while active, but must not block display of a usable cached result.

Version 1 does not need a complete offline dataset.

## 8. Data model

A suggested domain model is:

```swift
struct Taxon: Identifiable, Codable, Hashable, Sendable {
    let id: String              // Wikidata Q-ID
    let scientificName: String
    let rank: TaxonomicRank?
    let classification: Classification?
    let names: [LocalizedTaxonName]
    let externalIdentifiers: [ExternalIdentifier]
    let wikipediaSitelinks: [WikipediaSitelink]
}

struct LocalizedTaxonName: Codable, Hashable, Sendable {
    let languageCode: String
    let value: String
    let source: NameSource
    let regionCode: String?
    let isPreferred: Bool
}

struct Classification: Codable, Hashable, Sendable {
    let kingdom: String?
    let phylum: String?
    let taxonomicClass: String?
    let order: String?
    let family: String?
    let genus: String?
}

struct ExternalIdentifier: Codable, Hashable, Sendable {
    let authority: String
    let value: String
}

struct WikipediaSitelink: Codable, Hashable, Sendable {
    let languageCode: String
    let title: String
    let url: URL
}
```

The implementation may adapt these types, but it must preserve the distinction between canonical identity, scientific name, localized names, and external identifiers.

## 9. Data sources

### 9.1 Initial source: Wikidata

Wikidata is the initial canonical source because it provides stable entity identifiers, multilingual labels, taxonomic properties, aliases, and Wikipedia sitelinks.

The implementation should use the least expensive API route that satisfies each operation. Search and entity retrieval may use separate endpoints. Network code must be isolated behind a protocol so that fixtures and alternative providers can be used in tests.

### 9.2 Later sources

Potential later enrichments include:

- eBird/Clements for bird taxonomy, eBird species codes, regional common names, and alignment with Merlin.
- IOC World Bird List.
- GBIF.
- Catalogue of Life.
- iNaturalist.

Additional providers must enrich or reconcile a taxon; they must not replace the core domain model with provider-specific objects.

## 10. User interface

### 10.1 Main screen

The main screen should contain:

- A search field.
- Recent taxa when the field is empty.
- Search suggestions or candidates while searching.
- A result view after selection.

### 10.2 Result view

The result view should prioritize names rather than metadata. Each configured language appears as a row with its localized language label, taxon name, and copy affordance. The scientific name should use typographic italics where appropriate.

Secondary metadata such as family, rank, Q-ID, and source can be placed in a details section.

### 10.3 Settings

Settings must include:

- Configured languages and their order.
- Scientific-name position.
- Preferred Wikipedia language.
- Cache-clearing control.

Appearance should follow the system. A separate light/dark setting is unnecessary for version 1.

## 11. Architecture

Use SwiftUI for the application UI and App Intents for system integration.

Recommended module boundaries:

- `TaxonDomain`: Models and provider-independent rules.
- `WikidataClient`: Network requests and response mapping.
- `TaxonStore`: Cache and persistence.
- `TaxonFeatures`: Search and result presentation logic.
- App target.
- Share extension target.
- App Intents target or shared intent implementation as appropriate.

Prefer dependency injection through protocols. Network, cache, and settings services must be replaceable with test implementations.

SwiftData may be used for persistence, but the storage representation should not leak into the domain model or App Entity interface.

## 12. Error handling

The product must distinguish between:

- No matching taxon.
- Several plausible taxa.
- Requested language unavailable.
- Network unavailable with no cache.
- Wikidata response or decoding failure.
- Rate limiting or temporary server failure.

Errors should explain the next useful action. A missing French name, for example, is not the same failure as an unresolved taxon.

## 13. Privacy

Version 1 requires no account and should collect no personal data. Search text is sent only to the configured taxonomic data provider as required to perform a lookup.

Recent searches remain on device. Any future analytics must be opt-in or privacy-preserving and are outside the initial scope.

## 14. Accessibility and localization

All controls must have VoiceOver labels and support Dynamic Type. The result must remain readable at accessibility text sizes.

The application interface itself should be localizable independently from the taxon-language configuration. A user may run the interface in English while requesting Dutch, French, and German taxon names.

Scientific names must not be passed through normal interface localization.

## 15. Performance requirements

- A cached result should render effectively immediately.
- A normal online lookup should target completion within one second, excluding unusually slow network conditions.
- Search input should be debounced to avoid unnecessary requests.
- Duplicate in-flight requests for the same normalized query should be coalesced.
- The app and extension must remain responsive during network activity.

## 16. Testing requirements

The initial implementation must include:

- Unit tests for query normalization.
- Unit tests for Wikidata response mapping.
- Unit tests for configured language ordering and missing names.
- Unit tests for Wikipedia-language fallback.
- Unit tests for cache freshness behavior.
- App Intent tests where supported.
- UI tests for search, ambiguous candidate selection, result display, and copying.

Network tests must use recorded or constructed fixtures rather than depend on live Wikidata responses.

At minimum, fixtures should cover:

- `wespendief` resolving to *Pernis apivorus*.
- A scientific-name lookup.
- An accented common name.
- An ambiguous common name.
- A taxon missing one configured language.
- A non-taxonomic Wikidata search result that must be rejected.

## 17. Acceptance criteria for version 1

Version 1 is complete when:

1. A user can search for a supported common or scientific name and resolve it to the correct Wikidata taxon.
2. The result displays the scientific name and all available names in the user’s configured order.
3. The language list can be added to, removed from, and reordered.
4. A user can copy each name and the complete result.
5. Selected text can be sent to Taxon through the Share Sheet.
6. Shortcuts can resolve a taxon and retrieve a name for a selected language.
7. Wikipedia opens using a real Wikidata sitelink and follows the configured fallback order.
8. Recent successful lookups work from the local cache without a network connection.
9. Ambiguous input requires an explicit user choice.
10. Core lookup and presentation behavior is covered by automated tests.

## 18. Future roadmap

Likely later capabilities include:

- eBird/Clements enrichment and regional bird names.
- A configurable Merlin display language.
- Opening a bird directly in Merlin if Merlin publishes a supported species deep link or App Intent.
- Other external field-guide integrations.
- Synonyms and historical scientific names.
- Regional vernacular names.
- Full downloadable offline datasets.
- Images, maps, sounds, and richer taxonomic classification.
- OCR and camera-based text capture.
- macOS support.
- Broader Spotlight and Siri discovery.

## 19. Codex implementation brief

Codex should begin by creating an iOS SwiftUI project with a reusable domain layer, a mocked provider, and tests before integrating the live Wikidata API.

The preferred implementation sequence is:

1. Define domain models and provider protocols.
2. Add query normalization and deterministic fixture-based tests.
3. Implement the main search and result UI against a mock provider.
4. Implement the Wikidata client and map responses into domain models.
5. Add configurable language settings.
6. Add caching.
7. Add App Intents.
8. Add the Share extension.
9. Add Wikipedia sitelink opening and fallback behavior.
10. Run accessibility, localization, and offline-state checks.

Each phase should leave the project compiling and tests passing. Provider-specific types should remain confined to the provider module so that eBird, GBIF, or another source can be added later without rewriting the application.