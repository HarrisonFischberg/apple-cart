# Launch blockers

| # | Blocker | Type (missing fact / failed check / legal review / approval) | Owner | Needed for | Status |
| --- | --- | --- | --- | --- | --- |
| 1 | Public name. "Apple Cart" is a working title only: it contains Apple's trademark and App Review rejects such names. Pick a public name at the brand phase. | missing fact | Harold | Any public release | OPEN |
| 2 | Distribution: notarized direct download (decided 2026-11-14; 20 picks can't run sandboxed). | decision | Harold | — | CLOSED |
| 3 | Money model undecided (app is free for now; no paid or licensing code in v1). | missing fact | Harold | Launch | OPEN |
| 4 | Ralph fresh-context loop not cloned. | failed check | Claude | Phase 4 | OPEN |
| 6 | Charge control on macOS 26/27 unproven (native limit, calibration state ignores limits); spike T002 decides go/no-go. Partial result in docs/spikes/charge-control.md; AlDente's helper is installed on this Mac and must be quit and reset before any write test. | failed check | Claude + Harold present | M2 battery control | OPEN |
| 9 | Bundle identifier `app.rarecreatures.applecart` is provisional until the public name is chosen; changing it later resets settings and permissions. | missing fact | Harold | any shipped build | OPEN |
| 7 | Developer ID Application certificate needed for notarized builds; not yet confirmed on this Mac. | missing fact | Harold | T026 / release | OPEN |
| 8 | Minimum OS / chip: macOS 26+, Apple silicon only (approved 2026-11-14). | decision | Harold | — | CLOSED |
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
