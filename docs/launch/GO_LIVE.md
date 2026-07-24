# Taxon go-live plan

**Status:** Planning

**Release:** 1.0

**Owners:** TBD

This document tracks the operational work required to ship Taxon. Product scope
and acceptance criteria remain in [PRD.md](../../PRD.md).

The first delivery milestone is an internal TestFlight build installed on a
physical device, with live privacy and support URLs.

## Repository and service boundaries

Keep launch material with the application in this repository, separated by
concern:

- `docs/launch/` owns release checklists, App Store copy, privacy and support
  copy, and release runbooks.
- `website/` owns the static product, support, and privacy website.
- `.github/workflows/` owns CI and website deployment.

Keep App Store Connect state, tester lists, domain and DNS configuration,
support messages, certificates, provisioning profiles, credentials, and API
keys outside Git. Store deployment secrets in the relevant service or protected
GitHub environments.

A separate website repository is unnecessary while the site is a small Taxon
product surface. Reconsider that boundary only if the site gains a separate
team, technology stack, or release cadence.

## 1. Product release gate

- [ ] Complete or explicitly defer every v1 acceptance criterion in `PRD.md`.
- [ ] Implement and verify recent-result caching and offline behavior.
- [ ] Add UI coverage for search, ambiguity selection, results, and copying.
- [ ] Verify that distinct failure states remain actionable.
- [ ] Confirm the supported device family; retain iPad only after iPad QA.
- [ ] Add production AppIcon and AccentColor assets.
- [ ] Align app and Share Extension version and build values.
- [ ] Establish a monotonically increasing build-number policy.
- [ ] Update the Wikidata User-Agent with the shipping version and a durable
  contact URL.

## 2. Apple Developer and App Store Connect

- [ ] Verify current Apple Developer Program agreements, roles, and account
  status.
- [ ] Register and verify `com.axelgraff.taxon`.
- [ ] Register and verify `com.axelgraff.taxon.share`.
- [ ] Configure `group.com.axelgraff.taxon` for both targets.
- [ ] Create distribution signing and provisioning for the app and extension.
- [ ] Create the App Store Connect app record.
- [ ] Document the signing owner and whether releases are signed locally or by
  CI.
- [ ] Archive and validate a Release build.
- [ ] Upload an internal TestFlight build.
- [ ] Configure external testing, beta description, contact, and review notes.
- [ ] Document Share Sheet and Shortcuts review instructions.

Use a manual Xcode upload for the first builds. Automate uploads only after that
release path is understood and repeatable.

## 3. TestFlight acceptance

- [ ] Smoke-test on physical iPhone devices.
- [ ] Smoke-test on physical iPad devices if iPad remains supported.
- [ ] Verify Share Extension invocation, timeout, memory, and copy behavior.
- [ ] Verify App Intents and Shortcuts after first launch.
- [ ] Verify English, French, Dutch, and Italian UI.
- [ ] Verify VoiceOver, Dynamic Type, light and dark appearance, and
  accessibility text sizes.
- [ ] Verify ambiguous, non-taxonomic, missing-language, offline, rate-limited,
  network-failure, and decoding-failure states.
- [ ] Record a decision, owner, and target build for every tester issue.
- [ ] Complete at least one reliability beta and one release-candidate beta.
- [ ] Obtain release sign-off.

Start with a small external group representing the supported languages and
device families before expanding the beta.

## 4. Privacy, legal, and support

- [ ] Document the reviewed data flow, including lookup text sent to Wikidata
  and information retained on-device.
- [ ] Publish a privacy policy consistent with the implemented behavior.
- [ ] Complete the App Store privacy questionnaire from the data-flow inventory.
- [ ] Audit required-reason APIs and add a privacy manifest if required.
- [ ] Review source attribution and third-party licensing obligations.
- [ ] Establish a monitored support address and response owner.
- [ ] Publish support and troubleshooting pages.
- [ ] Keep third-party analytics disabled for v1 unless a separate privacy
  review approves and documents it.

Use TestFlight feedback, App Store Connect metrics, Xcode Organizer, and Apple's
crash reporting as the initial operational feedback loop.

## 5. Website

- [ ] Create a static site in `website/`.
- [ ] Add a product overview and App Store or TestFlight call to action.
- [ ] Add `/privacy`, `/support`, and contact information.
- [ ] Add release notes if they provide ongoing value.
- [ ] Configure a custom domain and HTTPS.
- [ ] Configure deployment from the default branch.
- [ ] Verify that URLs used by the app, User-Agent, and App Store Connect are
  durable.

GitHub Pages is sufficient for the initial static site. A different static host
can be adopted later without moving the source out of this repository.

## 6. App Store listing

- [ ] Prepare localized name, subtitle, description, keywords, and promotional
  text.
- [ ] Select category, age rating, copyright, pricing, and availability.
- [ ] Produce required screenshots for every retained device family.
- [ ] Complete export-compliance answers.
- [ ] Add privacy-policy, support, and marketing URLs.
- [ ] Add reviewer notes with precise Share Sheet and Shortcuts test steps.
- [ ] Review every locale in App Store Connect.
- [ ] Install and approve the submission build through TestFlight before
  submitting it.
- [ ] Use manual release for version 1.0.

## 7. CI/CD and release operations

- [ ] Add Swift package tests to CI.
- [ ] Add simulator build and app tests to CI.
- [ ] Regenerate with XcodeGen and fail CI on generated-project drift.
- [ ] Protect release secrets with GitHub environments.
- [ ] Document archive, validation, upload, rollback, and TestFlight build-expiry
  procedures.
- [ ] Add tagged releases and release notes.
- [ ] Automate TestFlight uploads only after the manual release path is proven.

When implementation begins, place App Store copy under
`docs/launch/app-store/`, reviewer instructions in
`docs/launch/app-store/review-notes.md`, and the repeatable release procedure in
`docs/launch/RELEASE_RUNBOOK.md`. Do not create empty placeholder files.

## 8. Monitoring and launch

- [ ] Review TestFlight feedback and crash reports before submission.
- [ ] Establish App Store Connect and Xcode Organizer health checks.
- [ ] Define the launch-day owner and rollback or escalation contacts.
- [ ] Submit for App Review.
- [ ] Verify the live listing, website, privacy, and support links.
- [ ] Monitor crashes, reviews, support, and provider failures after release.

## Release record

| Item | Value |
| --- | --- |
| Marketing version | 1.0 |
| Build | TBD |
| Commit | TBD |
| TestFlight sign-off | TBD |
| Submitted | TBD |
| Released | TBD |
