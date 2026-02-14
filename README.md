# Nudge

Nudge is a SwiftUI reminders client with Due-style repeating alerts for overdue tasks across iOS, iPadOS, and macOS.

## Project Layout

- `project.yml`: XcodeGen project definition for app targets and schemes.
- `Apps/iOS`, `Apps/macOS`: platform app entry points.
- `NagCorePackage`: shared package for reminders, scheduling, deep linking, persistence, and UI.
- `UITests/NudgeUITests`: UI tests with a debug notification simulator harness.

## Architecture

The project is split into an app shell and a shared package:

- `NagCorePackage/Sources/NagCore/Reminders`: EventKit abstraction (`RemindersRepository`) and concrete EventKit/mock implementations.
- `NagCorePackage/Sources/NagCore/Notifications`: scheduling (`NagScheduler`), orchestration (`NagEngine`), and notification clients.
- `NagCorePackage/Sources/NagCore/Persistence`: SwiftData stores for policy and session state.
- `NagCorePackage/Sources/NagCore/App`: deep-link routing, background refresh coordination, and app controller.
- `NagCorePackage/Sources/NagCore/UI`: shared SwiftUI views and view models.

## Permissions and Entitlements

Nudge needs:

- Reminder access (EventKit)
- Notification authorization (alerts, sound, badges, Time Sensitive)
- Background refresh scheduling on iOS

Entitlement files:

- `Nudge.entitlements`
- `Nudge-macOS.entitlements`

## Scheduling Constraints

The nag scheduler enforces rolling caps:

- Per-session cap (`perSessionCap`) for each reminder session
- Global cap (`globalCap`) across all scheduled notifications

Default strategy:

- Start sessions only for overdue reminders
- Stop sessions for completed or removed reminders
- Pause delivery while `snoozeUntil` is active
- Replenish notifications periodically via foreground refresh and background refresh hooks

## Critical Alerts Fallback

Nudge is scaffolded for Time Sensitive notifications by default.

Critical Alerts behavior is intentionally a fallback path because entitlement approval varies by app and environment. If Critical Alerts are unavailable, Nudge continues with Time Sensitive interruption level.

## Known Limitations

- Background task execution timing is controlled by system heuristics and cannot be guaranteed at exact intervals.
- EventKit sync timing and external reminder edits can cause short-lived UI staleness between refresh cycles.
- Critical Alerts require Apple approval and may not be available in local/dev builds.

## Development

Generate Xcode project:

```bash
xcodegen generate
```

Run package tests:

```bash
swift test --package-path NagCorePackage
```
