# Default View Redesign

**Date:** 2026-02-23
**Status:** Approved

## Problem

Nudge defaults to the "Today" smart list, which is too narrow for its primary use case: configuring which reminders get nagged. The 5-tab segmented picker (Today/Scheduled/All/Flagged/Completed) mirrors Apple Reminders but adds clutter for a nag-configuration app.

## Decision

Replace the 5-case `SmartList` enum with 2 cases and default to "Upcoming."

## Design

### SmartList enum

| Case | Display name | Filter |
|------|-------------|--------|
| `.upcoming` | Upcoming | Has due date, not completed |
| `.all` | All | Not completed |

Default: `.upcoming`

Removed cases: `.today`, `.flagged`, `.completed`

### UI

- Segmented picker shrinks from 5 to 2 segments: **Upcoming** | **All**
- List remains flat, sorted by due date
- Bell toggle (perReminder mode), swipe actions, search all unchanged

### Files affected

- `ReminderItem.swift` — `SmartList` enum: remove 3 cases, rename `.scheduled` to `.upcoming`
- `RemindersRepository.swift` — `filtered(for:)`: remove 3 cases, rename `.scheduled` to `.upcoming`
- `ReminderListViewModel.swift` — change default from `.today` to `.upcoming`
- `ReminderDashboardView.swift` — picker auto-updates via `SmartList.allCases`
- `MockRemindersRepository.swift` — update any references to removed cases
- Tests — update references to old SmartList cases
