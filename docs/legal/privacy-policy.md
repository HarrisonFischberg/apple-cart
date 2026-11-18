# Privacy policy (DRAFT)

> **NEEDS REVIEW** by a qualified person before publishing. Written 2026-11-18 from `docs/data-inventory.md`.
> Placeholders in [brackets] are unknown and must not be guessed (`docs/launch-blockers.md`).

Last updated: [date]

[App name] is made by [publisher legal name, ASSUMED Rare Creatures LLC], [business address]. Contact: [privacy contact].

## The short version

[App name] does not collect, sell or share personal data. There is no account, no analytics, no crash reporting, no
advertising and no AI service. Everything the app stores stays on your Mac.

## What stays on your Mac

- **Settings** for each tool you turn on.
- **Battery samples** (charge, temperature, watts, cycles) for the 24-hour graphs, deleted after 24 hours.
- **Clipboard history**, only while the Clipboard tool is on. Items marked as passwords or other sensitive types, and
  items copied from apps you exclude, are not stored. Items are kept 7 days by default (you can change this); pinned
  items are kept until you remove them.
- **System readings** (temperatures, CPU, GPU and memory use, app names) shown while the System view is open and not
  saved.
- **File lists** found by the uninstaller and cache cleaner, held only during a scan. Removed files go to the Trash.

You can delete everything the app stores with Settings > General > Delete all app data, or by deleting items in each
tool.

## The helper

The battery, fan and MagSafe light tools use a small helper that runs with administrator rights after you approve it.
It only talks to the app on your Mac and to the Mac's hardware controller. It stores nothing and never uses the network.
You can remove it from Settings at any time; removal returns charging, fans and the light to macOS.

## When the app uses the network

- **Update checks.** If you check for updates, or turn on automatic checks, the app asks GitHub Releases for the latest
  version. GitHub receives your IP address and the app version, under [GitHub's privacy statement](https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement).
- **Updates tool.** When you press Check now, macOS (`softwareupdate`) and Homebrew, if installed, contact their own
  servers as they do when you run them yourself. The app sends nothing of its own.
- **Debug info.** Send debug info opens a draft email in your Mail app with the app and macOS versions, Mac model, which
  tools are on and permission states. Nothing is sent unless you send that email.

## Permissions

Some tools ask for macOS permissions (for example Accessibility for plain paste, Screen Recording for copy text). Each
is asked for only when you turn on the tool that needs it, and you can revoke it in System Settings.

## Children

The app collects no personal data from anyone. [Minimum age, if any.]

## Changes

We will update this page and its date when the app's data use changes.
