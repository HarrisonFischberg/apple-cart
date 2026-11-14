# Architecture (replica-architect output)

Native macOS adaptation: there is no server, database or HTTP API. The full blueprint is `docs/blueprint.md`; this file is the replica-pack summary.

- **Stack in one line**: Swift 6 / SwiftUI + AppKit menu bar panel, one local Swift package for all logic, a launchd root helper over code-signed XPC, SwiftData + UserDefaults locally, Sparkle updates from GitHub Releases.
- **Stores**: 7 local entities (FeatureState, BatteryPolicy, ScheduleTask, ScheduleRun, BatterySample, ClipboardItem, small singletons). Schema with types, keys and retention in blueprint section 2.
- **Interface count**: 11 helper XPC calls (blueprint section 3); no network routes.
- **Riskiest parts**: (1) charge control on current macOS, decided by a spike before any battery-control code; (2) root helper security and survival across macOS updates; (3) Full Disk Access cleanup safety.
- **Build order**: vertical slice first (shell + read-only battery and system), then battery control, system, clean, clipboard and tools, release hardening. Each milestone lists its screens in blueprint section 9.
- **Next step**: Phase 3B design directions, then `/replica-design` in Phase 3C.
