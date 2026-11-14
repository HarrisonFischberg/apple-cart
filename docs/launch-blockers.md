# Launch blockers

| # | Blocker | Type (missing fact / failed check / legal review / approval) | Owner | Needed for | Status |
| --- | --- | --- | --- | --- | --- |
| 1 | Public name. "Apple Cart" is a working title only: it contains Apple's trademark and App Review rejects such names. Pick a public name at the brand phase. | missing fact | Harold | Any public release | OPEN |
| 2 | Distribution route (Mac App Store sandbox vs notarized direct download) is undecided; depends on which features are picked. | missing fact | Harold | Blueprint (Phase 3) | OPEN, decide at comparison stop |
| 3 | Money model undecided (app is free for now; no paid or licensing code in v1). | missing fact | Harold | Launch | OPEN |
| 4 | Ralph fresh-context loop not cloned. | failed check | Claude | Phase 4 | OPEN |
| 5 | Each chosen feature needing a macOS permission (Accessibility, Screen Recording, Full Disk Access, etc.) must be listed in the data inventory. | approval | Harold | Blueprint | OPEN |

## Intake answers (2026-11-14)

- One job: a Mac menu bar app that bundles the owner's a-la-carte pick of the best features from five reference apps.
- Platforms: macOS only. Stack: native Swift (SwiftUI + AppKit). AI only if a chosen feature needs it, recorded as a vendor first.
- Success in 30 days: free public app. Money: undecided.
- Accounts and data: no account, local only, works offline, no server.
- Constraints: no deadline; $0 services, ask before any spend.
- Design: native macOS look, light and dark.
- Out of scope: anything needing a server; paid/licensing code.
- Approval stops: all four (comparison, blueprint, design pick, repo creation).
- Analysis scope: public pages, store listings, help docs, and screenshots of the references only.

## ASSUMED (not asked; alternatives listed)

- Publisher: Rare Creatures LLC (from earlier projects). Alternative: personal name.
- Existing assets: Apple developer account and GitHub account HarrisonFischberg; no brand, logo, or domain for this app yet.
- iPhone/iPad companions: not planned (owner chose Mac only; not explicitly ruled out for later).

## Unknown business and legal inputs

Never infer these from a reference app. Never invent them.

- Legal entity and trading name: ASSUMED Rare Creatures LLC (confirm before launch)
- Business location: UNKNOWN
- Launch countries/states: UNKNOWN
- Public business contact: UNKNOWN
- Privacy contact: UNKNOWN
- Minimum user age / children may use: UNKNOWN
- Pricing, billing, trials, renewal: free for now; UNKNOWN long term
- Refund and cancellation terms: UNKNOWN
- Data types and sensitive data: none planned (local only); re-check per chosen feature
- Vendors, SDKs, analytics, AI providers, processors: none planned
- Retention or deletion exceptions: UNKNOWN
