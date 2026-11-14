# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

<!-- Nearest allowed value. The real target is native macOS only (a menu bar app); there is no iPhone, iPad, or web surface. Apply Apple-native guidance for the Mac, not iPhone layouts. -->

## Stack

Native Swift (SwiftUI + AppKit), chosen by the owner. No server. AI only if a chosen feature needs it, recorded as a vendor first.

## Users

Mac power users who already run several small menu bar utilities and want one tidy app holding only the tools they chose. The owner is the first user.

## Product Purpose

A free Mac menu bar app that bundles a hand-picked set of small system tools. Success in the first 30 days: a free public release that the owner uses daily.

## Positioning

Pick only what you want: every tool is an individual switch, off by default, so the app stays as small as the user's choices. Free, local, no account.

## Operating Context

Lives in the macOS menu bar and is used in short moments while doing other work. Works offline. Some tools may need macOS permissions (for example Accessibility); each is requested only when its tool is switched on.

## Capabilities and Constraints

- The tool list is undecided: it is chosen feature by feature after a comparison of five reference apps.
- No account, no sign-in, no server, no sync; all data stays on the Mac.
- No paid or licensing code in the first version; long-term pricing is undecided.
- No paid services or API spend without the owner's approval.
- Distribution (Mac App Store or notarized direct download) is undecided and depends on the chosen tools.

## Brand Commitments

- "Apple Cart" is a working title only and cannot be the public name (it contains Apple's trademark). The public name is undecided.
- Look follows native macOS, in light and dark.
- No logo, colors, or domain exist yet.

## Evidence on Hand

None yet. No users, reviews, testimonials, or benchmarks exist; future work must not invent any.

## Product Principles

1. Off by default: nothing runs until the user turns it on.
2. Each tool stands alone and can be removed without affecting the others.
3. Private by construction: local only, no account, no tracking.
4. Feels like part of macOS, not an app sitting on top of it.
5. Ask for a system permission only at the moment the tool that needs it is enabled, and say why.

## Accessibility & Inclusion

Full keyboard access and VoiceOver labels for every control; respect system text size, Reduce Motion, and Increase Contrast.
