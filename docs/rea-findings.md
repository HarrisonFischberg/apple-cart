# REA findings

Date: 2026-11-14. Authorized scope: public pages, store listings, help docs and public reviews of six reference apps (Sources A-F). No binaries, accounts or runtime analysis of the apps.

Method: REA `capture_browser_scenario` (headless Chromium 156, launch mode, 1280x720, light, reduced motion, service workers blocked) on each source's public product page. Every capture completed with no page errors.

## Observations

| Source | Kind of page | Triage result |
| --- | --- | --- |
| A | product site | native Mac app; site also queries a code-hosting API for release info |
| B | product page | native Mac app |
| C | product site | native Mac app |
| D | directory listing | native Mac app |
| E | product site | native Mac app |
| F | product page | native Mac app (battery management) |

## Verified vs inferred

- Verified: each URL is a marketing or listing page; no application logic runs in the browser.
- Inferred: feature behavior inside the apps (from page text and reviews), and which macOS permissions each feature needs (from how macOS works). None of the sources publishes a permission map.

## Limitations

- REA ended at triage for every source: deeper analysis would need the app binaries, which are outside the authorized scope.
- Public reviews were sparse for four of six sources.

## How findings inform the original build

The merged, source-free spec is in `replica/` (`recon.md`, `features.csv`, `prompts/`, `decisions.md`). Complaint-driven fixes are recorded there as notes on the matching features.
