# Nudge

Nudge is an ADHD nag layer on Apple Reminders with Due-style repeating alerts for overdue tasks across iOS, iPadOS, and macOS. It doesn't replace Reminders — it watches your existing lists and nags you about overdue items until you deal with them.

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

## Nag Modes

Nudge supports two modes for choosing which reminders to nag:

- **Per List** (default): Enable nagging for entire Reminders lists. All overdue items in enabled lists get nagged.
- **Per Reminder**: Opt in individual reminders via a bell toggle in the reminder list.

## Scheduling

The nag scheduler enforces rolling caps:

- Per-session cap (`perSessionCap`, default 5) for each reminder
- Global cap (`globalCap`, default 40) across all scheduled notifications

Nag loop:

- Sessions start for overdue reminders, stop for completed/removed ones, pause while snoozed
- `nagCount` tracks how many nags have fired per session
- Escalation: after a configurable number of nags, the interval shortens (e.g. 10 min → 2 min)
- Schedule replenishes on app foreground (`scenePhase == .active`) and via background refresh

## Actions

From notifications or the nag screen, you can:

- **Snooze** (configurable presets: 5, 10, 20, 60 min)
- **Mark Done** (completes the reminder in Apple Reminders)
- **Stop Nagging** (stops the nag session without completing the reminder)

All actions route through `NagEngine` for consistent state management.

## Known Limitations

- Background task execution timing is controlled by system heuristics and cannot be guaranteed at exact intervals.
- EventKit sync timing and external reminder edits can cause short-lived UI staleness between refresh cycles.

## Development

Generate Xcode project:

```bash
xcodegen generate
```

Run package tests:

```bash
swift test --package-path NagCorePackage
```
