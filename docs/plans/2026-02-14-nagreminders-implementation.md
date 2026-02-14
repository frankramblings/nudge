# Nudge Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a production-quality SwiftUI Reminders client with Due-like nagging behavior, quick snooze flows, and iOS/iPadOS/macOS support.

**Architecture:** A multi-target Xcode project generated with XcodeGen: shared `NagCore` framework for EventKit access, notification scheduling, persistence, and business logic; separate iOS and macOS app targets for platform UI and lifecycle hooks; unit/UI test bundles focused on scheduling behavior and notification-driven UX.

**Tech Stack:** Swift 5.10+, SwiftUI, EventKit, UserNotifications, BGTaskScheduler (iOS), SwiftData, XCTest, XCUITest, XcodeGen.

### Task 1: Scaffold Project and Targets

**Files:**
- Create: `project.yml`
- Create: `README.md`
- Create: `Nudge.entitlements`
- Create: `Nudge-macOS.entitlements`

**Step 1: Define project spec**
- Add app targets for iOS and macOS, shared framework target (`NagCore`), unit tests, and iOS UI tests.

**Step 2: Generate project**
- Run `xcodegen generate` in the repository root.

**Step 3: Commit checkpoint (local)**
- Stage project scaffolding.

### Task 2: Write Failing Core Scheduler Tests

**Files:**
- Create: `NagCorePackage/Tests/NagCoreTests/NagSchedulerTests.swift`

**Step 1: Write failing tests**
- Add tests for:
  - start session when overdue
  - stop session when completed
  - pause/resume on `snoozeUntil`
  - rolling scheduling caps and replenishment behavior

**Step 2: Verify RED**
- Run `xcodebuild test` for `NagCoreTests`.
- Expect compile/test failures due to missing production types.

**Step 3: Commit checkpoint (local)**
- Stage failing tests before implementation.

### Task 3: Implement Shared Domain Models and Storage

**Files:**
- Create: `NagCorePackage/Sources/NagCore/Models/NagPolicy.swift`
- Create: `NagCorePackage/Sources/NagCore/Models/NagSession.swift`
- Create: `NagCorePackage/Sources/NagCore/Models/AppSettings.swift`
- Create: `NagCorePackage/Sources/NagCore/Persistence/NagPolicyStore.swift`
- Create: `NagCorePackage/Sources/NagCore/Persistence/NagSessionStore.swift`

**Step 1: Implement SwiftData models and store protocols**
- Define global/per-reminder policy, session lifecycle fields, snooze state, counters, and caps.

**Step 2: Implement concrete SwiftData-backed stores**
- Add fetch/save/update/delete flows for policy/session data.

**Step 3: Re-run tests**
- Keep tests compiling by adding stubs and foundational types.

### Task 4: Implement EventKit Repository and Reminder CRUD

**Files:**
- Create: `NagCorePackage/Sources/NagCore/Reminders/RemindersRepository.swift`
- Create: `NagCorePackage/Sources/NagCore/Reminders/EventKitRemindersRepository.swift`
- Create: `NagCorePackage/Sources/NagCore/Reminders/MockRemindersRepository.swift`
- Create: `NagCorePackage/Sources/NagCore/Models/ReminderItem.swift`

**Step 1: Add async EventKit wrapper**
- Request access, list calendars, fetch reminders, create/update/complete/delete/move reminders.

**Step 2: Add event-store changed notifications**
- Publish refresh hooks for app lifecycle and pull-to-refresh.

### Task 5: Implement Notification and Scheduling Engine

**Files:**
- Create: `NagCorePackage/Sources/NagCore/Notifications/NotificationClient.swift`
- Create: `NagCorePackage/Sources/NagCore/Notifications/UserNotificationClient.swift`
- Create: `NagCorePackage/Sources/NagCore/Notifications/NagScheduler.swift`
- Create: `NagCorePackage/Sources/NagCore/Notifications/NagEngine.swift`
- Create: `NagCorePackage/Sources/NagCore/Notifications/NotificationConstants.swift`

**Step 1: Implement `NagScheduler` pure logic**
- Compute active sessions, next fire times, session caps, and global caps.

**Step 2: Implement notification actions/categories**
- Include Mark Done, snooze presets, and Snooze deep-link action.

**Step 3: Implement rolling-window scheduling**
- Keep at most K pending per session and total cap across sessions.

**Step 4: Apply interruption/sound policies**
- Time Sensitive default, Critical Alerts scaffolding and fallback path.

### Task 6: Implement App Coordinator + Deep Link Routing

**Files:**
- Create: `NagCorePackage/Sources/NagCore/App/DeepLinkRouter.swift`
- Create: `NagCorePackage/Sources/NagCore/App/BackgroundRefreshCoordinator.swift`
- Create: `NagCorePackage/Sources/NagCore/App/NagAppController.swift`

**Step 1: Deep-link handling**
- Route notification taps to reminder detail, quick snooze, and full-screen Nag Screen.

**Step 2: Background refresh**
- iOS BGAppRefresh task registration + replenishment call.
- macOS timer/lifecycle replenishment.

### Task 7: Implement Shared SwiftUI Views and ViewModels

**Files:**
- Create: `NagCorePackage/Sources/NagCore/UI/*`

**Step 1: Reminders-like list UI**
- Smart lists + reminder rows + inline add + swipe actions.

**Step 2: Due-inspired settings UI**
- Glass grouped sections with alert and auto-snooze controls.

**Step 3: Quick snooze UI**
- Grid of time-of-day and relative options with Mark Done / Stop Nagging.

**Step 4: Full-screen Nag Screen**
- Large Snooze button and slide-to-stop control.

### Task 8: Platform App Targets and Scene Wiring

**Files:**
- Create: `Apps/iOS/NudgeIOSApp.swift`
- Create: `Apps/macOS/NudgeMacApp.swift`
- Create: `Apps/iOS/Info.plist`
- Create: `Apps/macOS/Info.plist`

**Step 1: Wire model container and environment**
- Provide stores/repositories/controller via environment.

**Step 2: Platform navigation adaptation**
- iPhone `NavigationStack`; iPad/macOS `NavigationSplitView`.

### Task 9: Complete Tests (GREEN)

**Files:**
- Modify: `NagCorePackage/Tests/NagCoreTests/NagSchedulerTests.swift`
- Create: `UITests/NudgeUITests/DebugNotificationSimulatorUITests.swift`

**Step 1: Run unit tests**
- Verify scheduler tests pass.

**Step 2: Build UI test harness**
- Add Debug Notification Simulator controls and assertions.

**Step 3: Run UI tests**
- Validate delivered/action/open-Nag-Screen simulation.

### Task 10: Documentation and Verification

**Files:**
- Modify: `README.md`

**Step 1: Document architecture, permissions, and constraints**
- Include EventKit, notifications, rolling scheduling, background behavior, and Critical Alerts fallback.

**Step 2: Final verification**
- Build iOS + macOS targets and run tests.

**Step 3: Record known limitations**
- Note entitlement restrictions and OS behavior limits.
