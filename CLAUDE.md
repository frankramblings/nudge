# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

Generate Xcode project (required after changing `project.yml`):
```bash
xcodegen generate
```

Run NagCore package tests (preferred for unit testing):
```bash
swift test --package-path NagCorePackage
```

Run a single test:
```bash
swift test --package-path NagCorePackage --filter NagSchedulerTests/testName
```

Build the package without running tests:
```bash
swift build --package-path NagCorePackage
```

Build via Xcode schemes (iOS or macOS):
```bash
xcodebuild -scheme Nudge-iOS -destination 'platform=iOS Simulator,name=iPhone 16' build
xcodebuild -scheme Nudge-macOS build
```

## Architecture

Nudge is a SwiftUI reminders client with Due-style repeating nag alerts for overdue tasks. It targets iOS 17+ and macOS 14+ (Swift 5.10).

### Project Structure

The project uses **XcodeGen** (`project.yml`) to generate the Xcode project with thin platform app shells (`Apps/iOS`, `Apps/macOS`) that depend on a shared **NagCorePackage** Swift package containing all logic.

### NagCore Package Modules (`NagCorePackage/Sources/NagCore/`)

- **Models/**: Domain types — `NagPolicy` (repeat interval, escalation, `NagMode`), `NagSession` (active nag state with `nagCount` tracking), `ReminderItem` (reminder data + `SmartList` enum), `AppSettings`
- **Reminders/**: `RemindersRepository` protocol with `EventKitRemindersRepository` (real) and `MockRemindersRepository` (tests/previews)
- **Notifications/**: `NagScheduler` (pure scheduling algorithm — no side effects, highly testable), `NagEngine` (orchestrates scheduling + notification delivery + persistence), `NotificationClient` protocol with real/mock implementations, `NotificationConstants` (category/action IDs, deep-link factory)
- **Persistence/**: `NagPolicyStore` and `NagSessionStore` protocols backed by SwiftData (`NagPolicyRecord`, `NagSessionRecord` @Model types)
- **App/**: `NagAppController` (main @MainActor ObservableObject), `DeepLinkRouter` (URL parsing), `BackgroundRefreshCoordinator` (iOS BGAppRefresh / macOS Timer)
- **UI/**: SwiftUI views — `ReminderDashboardView` (main screen), `ReminderListView`/`ReminderListViewModel`, `QuickSnoozeView`, `PolicySettingsView`, `NagScreenView` (full-screen interruption)

### Key Design Patterns

- **Protocol-driven dependencies**: Repository, store, and notification client all use protocols with real and mock implementations for testability
- **Pure scheduling core**: `NagScheduler.buildSchedule()` is a pure function — all side effects (storage, notifications) happen in `NagEngine`
- **@MainActor for state**: `NagEngine` and `NagAppController` are `@MainActor`; all async methods use Swift concurrency (async/await)
- **SwiftData persistence**: Policy and session records stored via SwiftData; `ModelContainer` initialized at app startup and injected. Policy changes persist on settings dismiss via `ReminderListViewModel.savePolicy()`
- **Deep links**: `nudge://reminder`, `nudge://snooze`, `nudge://nag-screen` — parsed by `DeepLinkRouter`, handled by `NagAppController`. Dashboard observes `NagAppController` via `@EnvironmentObject` and shows nag screen via `fullScreenCover` (iOS) / `sheet` (macOS)
- **Action dispatch**: All snooze/markDone/stopNagging actions route through `NagAppController` → `NagEngine.handleNotificationAction()`, not through the view model directly

### Nag Modes

`NagMode` (stored on `NagPolicy`) controls which reminders get nagged:

- **`.perList`** (default): Reminders in lists whose IDs are in `nagEnabledListIDs` get nagged. Configure enabled lists in settings.
- **`.perReminder`**: Only reminders with an explicit per-reminder policy (`isEnabled: true`) get nagged. Toggle per-reminder in the reminder list UI.

### Scheduling Constraints

The nag scheduler enforces per-session (`perSessionCap`, default 5) and global (`globalCap`, default 40) rolling caps on scheduled notifications. Sessions start for overdue reminders, stop for completed/removed ones, and pause while snoozed. Date-only reminders (no time component) become due at a configurable hour (default 9 AM).

`NagEngine.replenishSchedule()` increments `nagCount` and sets `lastNagAt` on sessions after scheduling. Escalation kicks in when `nagCount >= escalationAfterNags`, switching to a shorter `escalationIntervalMinutes`. The iOS app replenishes on `scenePhase == .active` in addition to background refresh.
