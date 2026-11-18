# Apple Cart (working title)

A free, private Mac menu bar app for battery care and system upkeep: charge limit, sailing, top up, heat protection,
MagSafe light, fan control, keep awake, system monitor, clipboard history, copy text / read QR, uninstaller, cache
cleaner, update checks, break reminders and cleaning mode. Every tool is a switch, off by default. No account, no
server, no analytics.

"Apple Cart" is a working title only and will change before any public release (`docs/launch-blockers.md` #1).

## Status

Pre-release. The code lives on `phase-4/build`; `main` still holds only the planning docs. What is done and what is
left: `prd.md` (task table) and `docs/release-checklist.md`.

## Requirements

- macOS 26 or later, Apple silicon only.
- Xcode with Swift 6.2, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.46+.

## Build and test

```sh
scripts/fetch-sparkle.sh                      # pinned Sparkle 2.10.1 into Vendor/ (checksum verified)
swift test --package-path Packages/AppleCartKit
xcodegen generate
xcodebuild -scheme AppleCart -destination 'platform=macOS' -derivedDataPath .build/DerivedData build
```

The battery, fan and MagSafe light tools need the root helper (`Helper/`), installed from the app's Settings
(Install, then approve it in System Settings > General > Login Items). Any change under `Helper/` or
`Packages/AppleCartKit/Sources/HelperCore/` needs the installed helper removed and installed again before it runs.

## Layout

| Path | What |
| --- | --- |
| `App/` | AppKit shell: status item, panel, tool wiring, helper client, updater |
| `Helper/` | root launchd daemon entry point |
| `Packages/AppleCartKit` | all testable logic: `Core`, `UI`, `HelperProtocol`, `HelperCore` |
| `docs/` | blueprint, data inventory, audit, spikes, launch blockers, legal drafts |
| `spikes/` | one-off hardware probes, run only with the owner present |

## Licenses

Third-party notices: `docs/legal/third-party-notices.md`.
