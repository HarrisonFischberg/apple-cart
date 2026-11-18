# Release checklist

Written 2026-11-18 from `prd.md`, `docs/launch-blockers.md`, `docs/audit-2026-11-16.md` and the activity logs.
Tick every line before a public build. Nothing here deploys anything by itself.

## Every release

- [ ] Any change under `Helper/` or `Packages/AppleCartKit/Sources/HelperCore/` since the last release bumps
      `HelperIdentity.version` (`HelperProtocol/HelperXPC.swift`). Sparkle replaces the app but not the running
      daemon; without a bump the app keeps saying "Installed and working" and the fix never reaches anyone
      (audit 11). Update `chargeVersions` / `fanVersions` only if those calls changed.
- [ ] `CFBundleShortVersionString` and `CFBundleVersion` raised in `App/Info.plist` (and `Helper/Info.plist` when the
      helper changed).
- [ ] `swift test --package-path Packages/AppleCartKit` passes; Release build has zero warnings.
- [ ] Helper removed, the new build installed, and the battery, fan and light tools tried once on a real Mac.
- [ ] Release build signed with Developer ID, hardened runtime on, Sparkle framework signed with the same identity.
- [ ] Notarized and stapled: `spctl -a -vv` accepts the app, `xcrun stapler validate` passes (T026).
- [ ] Appcast signed with the Sparkle EdDSA key and uploaded next to the DMG on GitHub Releases.
- [ ] `docs/data-inventory.md`, `docs/legal/privacy-policy.md` and `docs/legal/third-party-notices.md` match the build.

## Before the first public release (open as of 2026-11-18)

- [ ] Public name chosen; bundle ID changed from the provisional `app.rarecreatures.applecart` (blockers 1, 9).
- [ ] Developer ID Application certificate on the build Mac (blocker 7).
- [ ] Sparkle EdDSA key generated and `SUPublicEDKey` added; updater turned on (blocker 10).
- [ ] Support address confirmed (blocker 11).
- [ ] Publisher and business details confirmed; legal drafts in `docs/legal/` reviewed by a qualified person (T025).
- [ ] Helper accepts only Developer ID signed callers in Release builds (audit 10).
- [ ] Charge control spike finished: sleep, reboot and helper-killed-mid-cut tests (T002, blocker 6).
- [ ] Accessibility pass (T024).
- [ ] `phase-4/build` merged into `main`.
