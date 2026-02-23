# Nudge v1 Completion Design

## Goal

Make Nudge a fully functional **nag layer on Apple Reminders** for ADHD users. Users manage reminders in Apple Reminders; Nudge reads from EventKit and handles persistent, repeating alerts until each overdue task is dealt with. iOS first, macOS later.

## Core Principles

- **Nag layer, not a reminders app** — no create/edit flows, no list management
- **Relentless nagging is the feature** — the nag loop (schedule → fire → repeat) must work end-to-end without gaps
- **Minimal dashboard** — for triage only (snooze, complete, stop nagging), not analytics
- **System DND over quiet hours** — no in-app quiet hours implementation

---

## 1. Fix the Core Nag Loop

### Nag count tracking

`NagSession.nagCount` is initialized to 0 and never incremented. `NagEngine.replenishSchedule()` must increment `nagCount` on each session when scheduling new notifications. This unblocks escalation — the scheduler already checks `nagCount >= escalationAfterNags` but never sees a count > 0.

### Snooze delay enforcement

`handleNotificationAction()` sets `snoozeUntil` and `nextEligibleAt`, but the scheduler ignores `nextEligibleAt`. `NagScheduler.buildSchedule()` must skip scheduling nags before `nextEligibleAt`, following the same pattern it already uses for `snoozeUntil`.

### Remove quiet hours from UI

Remove quiet hours controls from `PolicySettingsView`. Keep model fields dormant for potential future use. Users rely on system Do Not Disturb.

---

## 2. Fix Notification Interaction (Deep-Link Navigation)

`NagAppController` parses deep links and sets `@Published` properties (`nagScreenReminderID`, `quickSnoozeSelection`, `selectedReminderID`), but `ReminderDashboardView` never observes them.

### Wire deep-link state to UI

- `nagScreenReminderID` set → present `NagScreenView` as full-screen cover with actual reminder data (replace hardcoded "Debug Reminder")
- `quickSnoozeSelection` set → present `QuickSnoozeView` sheet with actual reminder
- `selectedReminderID` set → scroll to / highlight that reminder in the list

### Wire UI actions through NagEngine

`QuickSnoozeView` and `NagScreenView` actions (snooze, mark done, stop nagging) must call `NagEngine.handleNotificationAction()` so session state updates properly. Currently `ReminderListViewModel.snooze()` modifies the reminder's due date without touching the engine.

---

## 3. Policy Persistence & Nag Mode

### Fix policy persistence

`PolicySettingsView` binds to `@Published nagPolicy` on the view model but never saves. On settings sheet dismissal, call `policyStore.save()`. On launch, load saved global policy from store.

### Per-reminder vs. per-list nag mode

Add `NagMode` enum to settings:

- `.perReminder` — each reminder has an individual nag toggle (default off, user opts in)
- `.perList` — user selects which reminder lists nag (everything overdue in those lists nags automatically)

In per-reminder mode: dashboard shows a nag toggle on each reminder row.
In per-list mode: settings screen lets user pick which lists are "nag-enabled" via a `nagEnabledListIDs: Set<String>` on the global policy. Scheduler checks if reminder's `listID` is in the enabled set.

### Per-reminder escalation

Regardless of nag mode, escalation is per-reminder. Global policy provides defaults; per-reminder overrides stored in `NagPolicyStore` as already designed. Escalation fields: `escalationAfterNags` (nag count threshold) and `escalationIntervalMinutes` (shorter interval after threshold).

---

## 4. Harden Background Refresh & Strip Features

### Background refresh reliability

- Re-register next `BGAppRefreshTask` inside completion handler (already done)
- Call `replenishSchedule()` on every `scenePhase` change to `.active`
- Pre-schedule aggressively — fill all 40 global notification slots so nags fire even without background refresh for extended periods

### Strip unnecessary features

- **Remove** `addReminder()` from dashboard (nag layer, not reminders app)
- **Remove** quiet hours UI from `PolicySettingsView`
- **Remove** `AppSettings` UI (theme, sound, haptics) — struct stays, no settings screen for v1
- **Keep** debug panel (gated behind `--ui-test-debug-notifications` launch argument)

### Simplified dashboard

Smart list picker, reminder list with nag toggles (per-reminder mode) or plain list (per-list mode), swipe/tap actions for snooze/complete/stop, settings gear. Nothing else.

---

## 5. Test Coverage

### Nag loop tests

- Nag count increments when notifications are scheduled
- Escalation kicks in after N nags (shorter interval used)
- Snooze delay respected — no nags scheduled before `nextEligibleAt`

### Policy persistence tests

- Save global policy → reload → policy correct
- Per-reminder policy overrides global defaults
- Per-list mode: reminders in enabled lists get nagged, others don't

### Notification action tests

- Mark done from notification → reminder completed + session stopped
- Snooze from notification → session paused + resumes after delay
- Stop nagging → session stopped, reminder unchanged

All tests in `NagCoreTests`. Pure `NagScheduler` tests are highest value (no side effects). `NagEngine` tests use existing mock infrastructure.

---

## Platforms

iOS 17+ first. macOS 14+ as follow-up after iOS is solid.

## Out of Scope for v1

- Reminder create/edit/detail views
- List management (create, rename, color)
- Nag statistics or history display
- App settings (theme, sound, haptics)
- Quiet hours enforcement
- macOS polish
- Critical Alerts entitlement (Time Sensitive is sufficient)
