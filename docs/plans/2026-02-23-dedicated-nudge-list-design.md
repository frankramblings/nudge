# Dedicated Nudge List

**Date:** 2026-02-23
**Status:** Approved

## Problem

Nudge currently overlays nag behavior across all Reminders lists, requiring complex mode-based eligibility (perReminder vs perList). This makes the mental model unclear: which reminders will Nudge nag about? The answer depends on which mode you're in and which lists/reminders are toggled on.

## Decision

Nudge owns a single dedicated "Nudge" list within Apple Reminders. All nagging is scoped to reminders in that list. Users create reminders directly in Nudge (Due-style) or import them from other Reminders lists.

## Design

### EventKit integration

- On first launch (after Reminders permission), auto-create an EKCalendar called "Nudge." Store its `calendarIdentifier` in UserDefaults.
- If the list is deleted externally, detect and recreate on next launch.
- `RemindersRepository` gains: `ensureNudgeList() -> String` and `fetchReminders(inList:)`.
- Existing `moveReminder(id:to:)` handles imports.

### Data model changes

**Removed:**
- `SmartList` enum
- `NagMode` enum
- `nagEnabledListIDs` on `NagPolicy`
- `filtered(for:)` extension on `[ReminderItem]`

**NagPolicy keeps:** `isEnabled` (per-reminder, default `true`), `intervalMinutes`, `escalationAfterNags`, `escalationIntervalMinutes`, `dateOnlyDueHour`, `snoozePresetMinutes`, `repeatAtLeast`, `repeatIndefinitelyMode`.

### Main view

- No segmented picker. One flat list of all incomplete reminders in the Nudge list, sorted by due date.
- Each row: title, due date, nag-enabled bell icon (on by default).
- **Tap row** expands inline nag settings: interval, escalation, on/off toggle. Due-style.
- **Swipe actions:** delete, snooze.
- **Toolbar:** Add (Due-style), Import (from other lists), Settings (global defaults).

### Add reminder (Due-style)

- Title field, optional due date/time picker.
- Creates directly in the Nudge EventKit list.

### Import from Reminders

- Sheet showing all non-Nudge Reminders lists as expandable sections.
- Each section shows incomplete reminders.
- Multi-select, then "Import" moves selected reminders into the Nudge list.
- Move, not copy (no duplicates, native EventKit operation).

### Scheduler simplification

- No mode-based eligibility gating.
- Eligibility: reminder is in the Nudge list + overdue + per-reminder `isEnabled` (default `true`).
- `NagEngine.replenishSchedule()` fetches from Nudge list ID instead of `.all`.
- `NagScheduler.buildSchedule()` checks `perReminderPolicy?.isEnabled ?? true` (default flipped to true).

### Global settings

- Template for new reminders' nag intensity.
- Interval, escalation, repeat mode, date-only due hour, snooze presets.
- No more NagMode picker or list selector.

## Files affected

- `ReminderItem.swift` — remove `SmartList` enum
- `RemindersRepository.swift` — remove `filtered(for:)`, add `ensureNudgeList()`, `fetchReminders(inList:)`
- `EventKitRemindersRepository.swift` — implement new methods, list creation
- `MockRemindersRepository.swift` — implement new methods
- `NagPolicy.swift` — remove `NagMode`, `nagEnabledListIDs`
- `NagScheduler.swift` — simplify eligibility check
- `NagEngine.swift` — fetch from Nudge list ID
- `ReminderListViewModel.swift` — remove SmartList, fetch from Nudge list
- `ReminderDashboardView.swift` — remove picker, add toolbar buttons, inline expansion
- `ReminderListView.swift` — tap-to-expand inline settings
- `PolicySettingsView.swift` — remove mode picker, list selector
- New: `AddReminderView.swift` — Due-style add UI
- New: `ImportRemindersView.swift` — browse + multi-select + import sheet
- New: `InlineNagSettingsView.swift` — expandable per-reminder settings
- Tests — update for new API, add tests for list management + import
