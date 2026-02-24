# Default View Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the 5-case SmartList enum with 2 cases (Upcoming/All) and default to Upcoming, focusing the UI on nag configuration.

**Architecture:** SmartList enum shrinks from 5 to 2 cases. The `filtered(for:)` extension updates to match. The segmented picker auto-adapts via `SmartList.allCases`. No new files, no new dependencies.

**Tech Stack:** Swift 5.10, SwiftUI, NagCorePackage

---

### Task 1: Update SmartList enum and filter logic

**Files:**
- Modify: `NagCorePackage/Sources/NagCore/Models/ReminderItem.swift:86-94`
- Modify: `NagCorePackage/Sources/NagCore/Reminders/RemindersRepository.swift:14-35`

**Step 1: Update SmartList enum**

In `ReminderItem.swift`, replace the SmartList enum:

```swift
public enum SmartList: String, CaseIterable, Identifiable, Sendable {
  case upcoming = "Upcoming"
  case all = "All"

  public var id: String { rawValue }
}
```

**Step 2: Update filtered(for:) extension**

In `RemindersRepository.swift`, replace the `filtered(for:)` method:

```swift
public extension Array where Element == ReminderItem {
  func filtered(for smartList: SmartList, now: Date = Date(), calendar: Calendar = .current) -> [ReminderItem] {
    switch smartList {
    case .upcoming:
      return filter { $0.dueDate != nil && !$0.isCompleted }
    case .all:
      return filter { !$0.isCompleted }
    }
  }
}
```

**Step 3: Run tests to verify nothing breaks**

Run: `swift test --package-path NagCorePackage`
Expected: All 17 tests pass (no tests reference SmartList cases directly)

**Step 4: Commit**

```bash
git add NagCorePackage/Sources/NagCore/Models/ReminderItem.swift NagCorePackage/Sources/NagCore/Reminders/RemindersRepository.swift
git commit -m "refactor: reduce SmartList to Upcoming and All cases"
```

---

### Task 2: Update view model default

**Files:**
- Modify: `NagCorePackage/Sources/NagCore/UI/ReminderListViewModel.swift:6`

**Step 1: Change default SmartList**

In `ReminderListViewModel.swift` line 6, change:

```swift
@Published public var selectedSmartList: SmartList = .upcoming
```

**Step 2: Run tests to verify**

Run: `swift test --package-path NagCorePackage`
Expected: All tests pass

**Step 3: Commit**

```bash
git add NagCorePackage/Sources/NagCore/UI/ReminderListViewModel.swift
git commit -m "feat: default to Upcoming view for nag configuration"
```

---

### Task 3: Verify full build

**Step 1: Build the package**

Run: `swift build --package-path NagCorePackage`
Expected: Build succeeds with no errors

**Step 2: Run full test suite**

Run: `swift test --package-path NagCorePackage`
Expected: All 17 tests pass

**Step 3: Final commit (if any fixups needed)**

Only if previous steps required changes not yet committed.
