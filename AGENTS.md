# Taxon development conventions

## Product boundaries

- Keep the core model general to biological taxa. Do not introduce bird- or species-specific assumptions.
- Treat the Wikidata Q-ID and scientific name as canonical taxon identity. Provider-specific identifiers belong in source-specific enrichment records, never in the core identity.
- Keep localized names, their language codes, and source attribution distinct from scientific names.
- Do not add Merlin integration, image recognition, sounds, maps, observations, or a downloadable taxonomy database until the product scope changes.

## Module boundaries

- `TaxonDomain` is Foundation-only and provider-independent. It owns domain values, normalization, resolution rules, and provider protocols.
- `WikidataProvider` owns HTTP, Wikidata request/response DTOs, and mapping into `TaxonDomain`. Do not expose Wikidata DTOs outside this module.
- `Taxon` owns SwiftUI presentation, composition, App Intents adapters, and user settings.
- Keep App Intents adapters out of `TaxonDomain`; `AppEntity` conformance must not leak into reusable domain types.

## Swift conventions

- Use Swift 6 concurrency-aware APIs. Public domain values should be `Sendable` where appropriate.
- Favor small immutable value types. Inject dependencies through protocols; do not create hidden global service singletons.
- Preserve the distinction between no result, ambiguity, unavailable localized name, network failure, decoding failure, and rate limiting.
- Normalize query text locally for matching, but preserve the original text for provider requests and display.
- Model configured output languages as ordered source language codes, not just `Locale` values. Scientific name placement is a separate setting.

## Provider conventions

- Use Wikidata search APIs for text discovery and hydrate only bounded candidate Q-ID sets.
- Verify that candidates are taxa before presenting them as results.
- Use `P225` as the authoritative scientific name; do not replace it with a localized label.
- Derive Wikipedia URLs from Wikidata sitelinks rather than assembling URLs from labels.
- Network requests must provide a descriptive User-Agent, debounce interactive input, coalesce equivalent in-flight requests, and handle `Retry-After` for temporary failures.

## Testing and verification

- Keep network tests fixture-based; never depend on live Wikidata responses.
- Add or update unit tests with each change to parsing, normalization, resolution, language ordering, or fallback behavior.
- Test ambiguous and non-taxonomic search results explicitly. The UI must require selection rather than silently guessing.
- Build and test before handoff when the affected target is available. Record the exact command and result.

## Repository hygiene

- Use XcodeGen configuration in `project.yml`; regenerate the Xcode project after target or build-setting changes and commit generated project changes when present.
- Keep commits focused and reviewable. Do not combine unrelated formatting or generated-file churn with behavior changes.
- Update `README.md` when changing module boundaries, build prerequisites, or supported workflows.
