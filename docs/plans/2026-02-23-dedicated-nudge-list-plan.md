# Dedicated Nudge List Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the multi-list/multi-mode nag system with a single dedicated "Nudge" list in Apple Reminders, with Due-style add, import from other lists, and tap-to-expand inline nag settings.

**Architecture:** The app auto-creates a "Nudge" EKCalendar on first launch and stores its ID. All fetching is scoped to that list. NagMode and SmartList are removed. Every reminder in the Nudge list is nagged by default with per-reminder intensity settings. The scheduler simplifies to: overdue + isEnabled (default true).

**Tech Stack:** Swift 5.10, SwiftUI, EventKit, SwiftData, NagCorePackage

---

### Task 1: Remove SmartList enum and update RemindersRepository protocol

**Files:**
- Modify: `NagCorePackage/Sources/NagCore/Models/ReminderItem.swift`
- Modify: `NagCorePackage/Sources/NagCore/Reminders/RemindersRepository.swift`

**Step 1: Remove SmartList enum from ReminderItem.swift**

Delete the entire `SmartList` enum (lines 86-91). The file should end after the `ReminderDraft` struct.

**Step 2: Remove filtered(for:) and update RemindersRepository protocol**

In `RemindersRepository.swift`, replace the entire file with:

```swift
import Foundation

public protocol RemindersRepository: AnyObject {
  func requestAccess() async throws -> Bool
  func fetchLists() async throws -> [ReminderList]
  func fetchReminders(inList listID: String) async throws -> [ReminderItem]
  func fetchAllReminders() async throws -> [ReminderItem]
  func ensureNudgeList() async throws -> String
  func saveReminder(_ draft: ReminderDraft) async throws -> ReminderItem
  func setCompleted(reminderID: String, isCompleted: Bool) async throws
  func deleteReminder(id: String) async throws
  func moveReminder(id: String, to listID: String) async throws
  func setStoreChangedHandler(_ handler: (@Sendable () -> Void)?)
}
```

`fetchReminders(inList:)` replaces the old `fetchReminders(in: SmartList)`. `fetchAllReminders()` is for the import view. `ensureNudgeList()` creates or finds the Nudge calendar.

**Step 3: Run tests to check what breaks**

Run: `swift test --package-path NagCorePackage 2>&1 || true`
Expected: Compilation errors — tests, mock, engine all reference the old API. This is expected; we'll fix them in subsequent tasks.

**Step 4: Commit**

```bash
git add NagCorePackage/Sources/NagCore/Models/ReminderItem.swift NagCorePackage/Sources/NagCore/Reminders/RemindersRepository.swift
git commit -m "refactor: remove SmartList, update RemindersRepository protocol for dedicated list"
```

---

### Task 2: Remove NagMode from NagPolicy and simplify persistence

**Files:**
- Modify: `NagCorePackage/Sources/NagCore/Models/NagPolicy.swift`
- Modify: `NagCorePackage/Sources/NagCore/Persistence/NagPolicyStore.swift`

**Step 1: Remove NagMode enum and simplify NagPolicy**

Replace `NagCorePackage/Sources/NagCore/Models/NagPolicy.swift` with:

```swift
import Foundation

public enum RepeatIndefinitelyMode: String, CaseIterable, Codable, Sendable {
  case off
  case whenPossible
  case always
}

public struct NagPolicy: Equatable, Codable, Sendable {
  public var isEnabled: Bool
  public var intervalMinutes: Int
  public var customIntervalMinutes: Int?
  public var quietHoursEnabled: Bool
  public var quietHoursStartHour: Int
  public var quietHoursEndHour: Int
  public var escalationAfterNags: Int?
  public var escalationIntervalMinutes: Int?
  public var dateOnlyDueHour: Int
  public var repeatAtLeast: Int
  public var repeatIndefinitelyMode: RepeatIndefinitelyMode
  public var snoozePresetMinutes: [Int]

  public init(
    isEnabled: Bool = true,
    intervalMinutes: Int = 10,
    customIntervalMinutes: Int? = nil,
    quietHoursEnabled: Bool = false,
    quietHoursStartHour: Int = 22,
    quietHoursEndHour: Int = 7,
    escalationAfterNags: Int? = nil,
    escalationIntervalMinutes: Int? = nil,
    dateOnlyDueHour: Int = 9,
    repeatAtLeast: Int = 10,
    repeatIndefinitelyMode: RepeatIndefinitelyMode = .whenPossible,
    snoozePresetMinutes: [Int] = [5, 10, 20, 60]
  ) {
    self.isEnabled = isEnabled
    self.intervalMinutes = intervalMinutes
    self.customIntervalMinutes = customIntervalMinutes
    self.quietHoursEnabled = quietHoursEnabled
    self.quietHoursStartHour = quietHoursStartHour
    self.quietHoursEndHour = quietHoursEndHour
    self.escalationAfterNags = escalationAfterNags
    self.escalationIntervalMinutes = escalationIntervalMinutes
    self.dateOnlyDueHour = dateOnlyDueHour
    self.repeatAtLeast = repeatAtLeast
    self.repeatIndefinitelyMode = repeatIndefinitelyMode
    self.snoozePresetMinutes = snoozePresetMinutes
  }

  public var effectiveIntervalMinutes: Int {
    customIntervalMinutes ?? intervalMinutes
  }

  public static let `default` = NagPolicy()
}
```

**Step 2: Update NagPolicyRecord and SwiftDataNagPolicyStore**

In `NagCorePackage/Sources/NagCore/Persistence/NagPolicyStore.swift`:

Remove the `nagModeRaw` and `nagEnabledListIDsRaw` properties from `NagPolicyRecord` (keep the properties but stop using them — SwiftData handles migration). Actually, for simplicity, keep them on the @Model so SwiftData doesn't crash on existing data, but stop reading/writing them in the store logic.

In `SwiftDataNagPolicyStore`:
- In `save(_:for:)`, remove the lines that set `nagModeRaw` and `nagEnabledListIDsRaw`.
- In `apply(policy:to:)`, remove the lines that set `nagModeRaw` and `nagEnabledListIDsRaw`.
- In `decode(record:)`, remove the `nagMode` and `nagEnabledListIDs` parameters from the `NagPolicy` init call.

**Step 3: Commit**

```bash
git add NagCorePackage/Sources/NagCore/Models/NagPolicy.swift NagCorePackage/Sources/NagCore/Persistence/NagPolicyStore.swift
git commit -m "refactor: remove NagMode from NagPolicy and persistence layer"
```

---

### Task 3: Update EventKitRemindersRepository for dedicated list

**Files:**
- Modify: `NagCorePackage/Sources/NagCore/Reminders/EventKitRemindersRepository.swift`

**Step 1: Implement new protocol methods**

Replace `fetchReminders(in:)` with `fetchReminders(inList:)` and `fetchAllReminders()`. Add `ensureNudgeList()`. The full updated file:

```swift
import EventKit
import Foundation

public final class EventKitRemindersRepository: RemindersRepository {
  private let eventStore: EKEventStore
  private let notificationCenter: NotificationCenter
  private var storeChangedHandler: (@Sendable () -> Void)?
  private var observer: NSObjectProtocol?

  private static let nudgeListKey = "com.nudge.listID"

  public init(
    eventStore: EKEventStore = EKEventStore(),
    notificationCenter: NotificationCenter = .default
  ) {
    self.eventStore = eventStore
    self.notificationCenter = notificationCenter
  }

  deinit {
    if let observer {
      notificationCenter.removeObserver(observer)
    }
  }

  public func requestAccess() async throws -> Bool {
    try await eventStore.requestFullAccessToReminders()
  }

  public func ensureNudgeList() async throws -> String {
    if let existingID = UserDefaults.standard.string(forKey: Self.nudgeListKey),
       eventStore.calendar(withIdentifier: existingID) != nil {
      return existingID
    }

    // Check if a list named "Nudge" already exists
    if let existing = eventStore.calendars(for: .reminder).first(where: { $0.title == "Nudge" }) {
      UserDefaults.standard.set(existing.calendarIdentifier, forKey: Self.nudgeListKey)
      return existing.calendarIdentifier
    }

    let calendar = EKCalendar(for: .reminder, eventStore: eventStore)
    calendar.title = "Nudge"
    calendar.source = eventStore.defaultCalendarForNewReminders()?.source
    try eventStore.saveCalendar(calendar, commit: true)
    UserDefaults.standard.set(calendar.calendarIdentifier, forKey: Self.nudgeListKey)
    return calendar.calendarIdentifier
  }

  public func fetchLists() async throws -> [ReminderList] {
    eventStore
      .calendars(for: .reminder)
      .map { ReminderList(id: $0.calendarIdentifier, title: $0.title) }
      .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
  }

  public func fetchReminders(inList listID: String) async throws -> [ReminderItem] {
    guard let calendar = eventStore.calendar(withIdentifier: listID) else {
      return []
    }
    let predicate = eventStore.predicateForReminders(in: [calendar])
    let reminders = try await fetchReminders(matching: predicate)
    return reminders
      .map(mapReminder)
      .filter { !$0.isCompleted }
      .sorted(byDueDate: true)
  }

  public func fetchAllReminders() async throws -> [ReminderItem] {
    let predicate = eventStore.predicateForReminders(in: nil)
    let reminders = try await fetchReminders(matching: predicate)
    return reminders
      .map(mapReminder)
      .filter { !$0.isCompleted }
      .sorted(byDueDate: true)
  }

  public func saveReminder(_ draft: ReminderDraft) async throws -> ReminderItem {
    let reminder = try reminderForSave(draft: draft)

    reminder.title = draft.title
    reminder.notes = draft.notes
    reminder.isCompleted = draft.isCompleted
    reminder.priority = draft.priority

    if let dueDate = draft.dueDate {
      if draft.hasTimeComponent {
        reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
      } else {
        reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: dueDate)
      }
    } else {
      reminder.dueDateComponents = nil
    }

    reminder.calendar = eventStore.calendar(withIdentifier: draft.listID) ?? eventStore.defaultCalendarForNewReminders()

    try eventStore.save(reminder, commit: true)
    return mapReminder(reminder)
  }

  public func setCompleted(reminderID: String, isCompleted: Bool) async throws {
    guard let reminder = eventStore.calendarItem(withIdentifier: reminderID) as? EKReminder else {
      return
    }

    reminder.isCompleted = isCompleted
    try eventStore.save(reminder, commit: true)
  }

  public func deleteReminder(id: String) async throws {
    guard let reminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder else {
      return
    }

    try eventStore.remove(reminder, commit: true)
  }

  public func moveReminder(id: String, to listID: String) async throws {
    guard let reminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder,
          let calendar = eventStore.calendar(withIdentifier: listID) else {
      return
    }

    reminder.calendar = calendar
    try eventStore.save(reminder, commit: true)
  }

  public func setStoreChangedHandler(_ handler: (@Sendable () -> Void)?) {
    storeChangedHandler = handler

    if let observer {
      notificationCenter.removeObserver(observer)
      self.observer = nil
    }

    guard handler != nil else {
      return
    }

    observer = notificationCenter.addObserver(
      forName: .EKEventStoreChanged,
      object: eventStore,
      queue: .main
    ) { [weak self] _ in
      self?.storeChangedHandler?()
    }
  }

  private func reminderForSave(draft: ReminderDraft) throws -> EKReminder {
    if let id = draft.id,
       let existing = eventStore.calendarItem(withIdentifier: id) as? EKReminder {
      return existing
    }

    guard let defaultCalendar = eventStore.defaultCalendarForNewReminders() else {
      throw NSError(domain: "EventKitRemindersRepository", code: 1)
    }

    let reminder = EKReminder(eventStore: eventStore)
    reminder.calendar = defaultCalendar
    return reminder
  }

  private func fetchReminders(matching predicate: NSPredicate) async throws -> [EKReminder] {
    try await withCheckedThrowingContinuation { continuation in
      eventStore.fetchReminders(matching: predicate) { reminders in
        continuation.resume(returning: reminders ?? [])
      }
    }
  }

  private func mapReminder(_ reminder: EKReminder) -> ReminderItem {
    let dueDate = reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
    let hasTimeComponent = reminder.dueDateComponents?.hour != nil || reminder.dueDateComponents?.minute != nil

    return ReminderItem(
      id: reminder.calendarItemIdentifier,
      title: reminder.title,
      notes: reminder.notes,
      dueDate: dueDate,
      isCompleted: reminder.isCompleted,
      isFlagged: reminder.priority > 5,
      priority: reminder.priority,
      listID: reminder.calendar.calendarIdentifier,
      listTitle: reminder.calendar.title,
      hasTimeComponent: hasTimeComponent
    )
  }
}

private extension Array where Element == ReminderItem {
  func sorted(byDueDate ascending: Bool) -> [ReminderItem] {
    sorted { lhs, rhs in
      switch (lhs.dueDate, rhs.dueDate) {
      case let (lhsDate?, rhsDate?):
        return ascending ? lhsDate < rhsDate : lhsDate > rhsDate
      case (_?, nil):
        return true
      case (nil, _?):
        return false
      case (nil, nil):
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
      }
    }
  }
}
```

**Step 2: Commit**

```bash
git add NagCorePackage/Sources/NagCore/Reminders/EventKitRemindersRepository.swift
git commit -m "feat: implement dedicated Nudge list in EventKitRemindersRepository"
```

---

### Task 4: Update MockRemindersRepository

**Files:**
- Modify: `NagCorePackage/Sources/NagCore/Reminders/MockRemindersRepository.swift`

**Step 1: Implement new protocol methods**

Replace the entire file:

```swift
import Foundation

public final class MockRemindersRepository: RemindersRepository {
  public private(set) var completedReminderIDs: [String] = []

  private var reminders: [ReminderItem]
  private var storeChangedHandler: (@Sendable () -> Void)?
  private let nudgeListID: String

  public init(reminders: [ReminderItem] = MockRemindersRepository.defaultReminders(), nudgeListID: String = "nudge") {
    self.reminders = reminders
    self.nudgeListID = nudgeListID
  }

  public func requestAccess() async throws -> Bool {
    true
  }

  public func ensureNudgeList() async throws -> String {
    nudgeListID
  }

  public func fetchLists() async throws -> [ReminderList] {
    let grouped = Dictionary(grouping: reminders, by: \.listID)
    return grouped
      .map { listID, reminders in
        ReminderList(id: listID, title: reminders.first?.listTitle ?? "List")
      }
      .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
  }

  public func fetchReminders(inList listID: String) async throws -> [ReminderItem] {
    reminders
      .filter { $0.listID == listID && !$0.isCompleted }
      .sorted { lhs, rhs in
        switch (lhs.dueDate, rhs.dueDate) {
        case let (lhsDate?, rhsDate?):
          return lhsDate < rhsDate
        case (nil, _?):
          return false
        case (_?, nil):
          return true
        case (nil, nil):
          return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
      }
  }

  public func fetchAllReminders() async throws -> [ReminderItem] {
    reminders
      .filter { !$0.isCompleted }
      .sorted { lhs, rhs in
        switch (lhs.dueDate, rhs.dueDate) {
        case let (lhsDate?, rhsDate?):
          return lhsDate < rhsDate
        case (nil, _?):
          return false
        case (_?, nil):
          return true
        case (nil, nil):
          return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
      }
  }

  public func saveReminder(_ draft: ReminderDraft) async throws -> ReminderItem {
    let reminderID = draft.id ?? UUID().uuidString
    let listTitle = reminders.first(where: { $0.listID == draft.listID })?.listTitle ?? "Nudge"

    let reminder = ReminderItem(
      id: reminderID,
      title: draft.title,
      notes: draft.notes,
      dueDate: draft.dueDate,
      isCompleted: draft.isCompleted,
      isFlagged: draft.isFlagged,
      priority: draft.priority,
      listID: draft.listID,
      listTitle: listTitle,
      hasTimeComponent: draft.hasTimeComponent
    )

    if let existingIndex = reminders.firstIndex(where: { $0.id == reminderID }) {
      reminders[existingIndex] = reminder
    } else {
      reminders.append(reminder)
    }

    storeChangedHandler?()
    return reminder
  }

  public func setCompleted(reminderID: String, isCompleted: Bool) async throws {
    if let index = reminders.firstIndex(where: { $0.id == reminderID }) {
      reminders[index].isCompleted = isCompleted
    }
    if isCompleted {
      completedReminderIDs.append(reminderID)
    }
    storeChangedHandler?()
  }

  public func deleteReminder(id: String) async throws {
    reminders.removeAll { $0.id == id }
    storeChangedHandler?()
  }

  public func moveReminder(id: String, to listID: String) async throws {
    guard let index = reminders.firstIndex(where: { $0.id == id }) else {
      return
    }

    reminders[index].listID = listID
    reminders[index].listTitle = "Nudge"
    storeChangedHandler?()
  }

  public func setStoreChangedHandler(_ handler: (@Sendable () -> Void)?) {
    storeChangedHandler = handler
  }

  public func simulateStoreChange() {
    storeChangedHandler?()
  }

  public static func sampleData() -> MockRemindersRepository {
    MockRemindersRepository(reminders: defaultReminders())
  }

  public static func defaultReminders() -> [ReminderItem] {
    let now = Date()
    return [
      ReminderItem(
        id: "sample-1",
        title: "Check in with Alex",
        notes: "Discuss sprint scope",
        dueDate: now.addingTimeInterval(-30 * 60),
        isCompleted: false,
        isFlagged: true,
        priority: 1,
        listID: "nudge",
        listTitle: "Nudge",
        hasTimeComponent: true
      ),
      ReminderItem(
        id: "sample-2",
        title: "Bring package to post office",
        notes: nil,
        dueDate: now.addingTimeInterval(2 * 60 * 60),
        isCompleted: false,
        isFlagged: false,
        priority: 0,
        listID: "nudge",
        listTitle: "Nudge",
        hasTimeComponent: true
      ),
      ReminderItem(
        id: "sample-3",
        title: "Book dentist appointment",
        notes: nil,
        dueDate: now.addingTimeInterval(-24 * 60 * 60),
        isCompleted: true,
        isFlagged: false,
        priority: 0,
        listID: "nudge",
        listTitle: "Nudge",
        hasTimeComponent: false
      ),
    ]
  }
}
```

**Step 2: Commit**

```bash
git add NagCorePackage/Sources/NagCore/Reminders/MockRemindersRepository.swift
git commit -m "refactor: update MockRemindersRepository for dedicated list API"
```

---

### Task 5: Simplify NagScheduler eligibility

**Files:**
- Modify: `NagCorePackage/Sources/NagCore/Notifications/NagScheduler.swift`

**Step 1: Remove mode-based eligibility from buildSchedule**

In `NagScheduler.swift`, replace the `isNagEnabled` block (lines 29-35) with:

```swift
      let isNagEnabled = perReminderPolicy?.isEnabled ?? true
```

This single line replaces the entire `switch globalPolicy.nagMode` block. Default is `true` — every reminder in the Nudge list is nagged unless explicitly disabled.

**Step 2: Run tests**

Run: `swift test --package-path NagCorePackage 2>&1 || true`
Expected: Some tests still fail due to remaining SmartList references in test helpers or the engine. We'll fix those next.

**Step 3: Commit**

```bash
git add NagCorePackage/Sources/NagCore/Notifications/NagScheduler.swift
git commit -m "refactor: simplify NagScheduler eligibility to per-reminder isEnabled"
```

---

### Task 6: Update NagEngine to use Nudge list

**Files:**
- Modify: `NagCorePackage/Sources/NagCore/Notifications/NagEngine.swift`

**Step 1: Update replenishSchedule to fetch from Nudge list**

In `NagEngine.swift`, change line 38 from:

```swift
    let reminders = try await remindersRepository.fetchReminders(in: .all)
```

to:

```swift
    let nudgeListID = try await remindersRepository.ensureNudgeList()
    let reminders = try await remindersRepository.fetchReminders(inList: nudgeListID)
```

Everything else in the engine stays the same.

**Step 2: Commit**

```bash
git add NagCorePackage/Sources/NagCore/Notifications/NagEngine.swift
git commit -m "feat: NagEngine fetches from dedicated Nudge list"
```

---

### Task 7: Update tests for new API

**Files:**
- Modify: `NagCorePackage/Tests/NagCoreTests/NagSchedulerTests.swift`
- Modify: `NagCorePackage/Tests/NagCoreTests/NagEngineTests.swift`

**Step 1: Update NagSchedulerTests**

The tests that reference `nagMode` and `nagEnabledListIDs` need updating:

- `testPerReminderModeOnlyNagsOptedInReminders`: Rename to `testOnlyNagsRemindersWithPolicyEnabled`. Remove the `nagMode: .perReminder` from globalPolicy. The test logic is the same — reminders without an explicit `isEnabled: true` policy don't get nagged... actually wait, with the new default (`isEnabled ?? true`), reminders WITHOUT a policy ARE nagged. So this test needs to verify that reminders with `isEnabled: false` are NOT nagged. Update accordingly.

- `testPerListModeNagsRemindersInEnabledLists`: Remove entirely. There's no per-list mode anymore.

Update the `globalPolicy` construction in all tests to remove `nagMode` and `nagEnabledListIDs` parameters.

**Step 2: Update NagEngineTests**

- `testReplenishScheduleRespectsPerListMode`: Remove entirely.
- Update `MockRemindersRepository` usage — the engine tests create their own mock repos with specific reminders. Change `fetchReminders(in:)` calls to use the new API. Since `MockRemindersRepository` now takes a `nudgeListID` and the engine calls `ensureNudgeList()` + `fetchReminders(inList:)`, ensure test reminders use `listID: "nudge"` to match.
- Update the `StubNagPolicyStore` in the test file to remove `nagMode`/`nagEnabledListIDs` from any `NagPolicy` construction.

**Step 3: Run tests**

Run: `swift test --package-path NagCorePackage`
Expected: All tests pass (will be fewer tests since we removed 2)

**Step 4: Commit**

```bash
git add NagCorePackage/Tests/NagCoreTests/NagSchedulerTests.swift NagCorePackage/Tests/NagCoreTests/NagEngineTests.swift
git commit -m "test: update tests for dedicated list API, remove mode-based tests"
```

---

### Task 8: Update ReminderListViewModel for dedicated list

**Files:**
- Modify: `NagCorePackage/Sources/NagCore/UI/ReminderListViewModel.swift`

**Step 1: Remove SmartList, fetch from Nudge list**

Replace the entire file:

```swift
import Foundation

@MainActor
public final class ReminderListViewModel: ObservableObject {
  @Published public private(set) var reminders: [ReminderItem] = []
  @Published public var searchText = ""
  @Published public var isLoading = false
  @Published public var errorMessage: String?
  @Published public var nagPolicy: NagPolicy = .default
  @Published public private(set) var nagStates: [String: Bool] = [:]
  @Published public private(set) var nudgeListID: String?

  private let remindersRepository: any RemindersRepository
  private let policyStore: (any NagPolicyStore)?

  public init(
    remindersRepository: any RemindersRepository = MockRemindersRepository.sampleData(),
    policyStore: (any NagPolicyStore)? = nil
  ) {
    self.remindersRepository = remindersRepository
    self.policyStore = policyStore
    if let store = policyStore {
      self.nagPolicy = store.globalPolicy()
    }
    self.remindersRepository.setStoreChangedHandler { [weak self] in
      Task {
        await self?.refresh()
      }
    }
  }

  public func savePolicy() {
    try? policyStore?.save(nagPolicy, for: nil)
  }

  public var visibleReminders: [ReminderItem] {
    guard !searchText.isEmpty else {
      return reminders
    }

    let query = searchText.lowercased()
    return reminders.filter {
      $0.title.lowercased().contains(query) || ($0.notes?.lowercased().contains(query) ?? false)
    }
  }

  public func refresh() async {
    isLoading = true
    defer { isLoading = false }

    do {
      let listID = try await remindersRepository.ensureNudgeList()
      nudgeListID = listID
      reminders = try await remindersRepository.fetchReminders(inList: listID)
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
    loadNagStates()
  }

  public func loadNagStates() {
    guard let store = policyStore else {
      nagStates = [:]
      return
    }
    let policies = store.allPoliciesByReminderID()
    // Default is true (nagged) — only store explicit overrides
    var states: [String: Bool] = [:]
    for reminder in reminders {
      states[reminder.id] = policies[reminder.id]?.isEnabled ?? true
    }
    nagStates = states
  }

  public func toggleNag(for reminder: ReminderItem) {
    guard let store = policyStore else { return }
    let current = nagStates[reminder.id] ?? true
    var policy = store.policy(for: reminder.id) ?? nagPolicy
    policy.isEnabled = !current
    try? store.save(policy, for: reminder.id)
    nagStates[reminder.id] = !current
  }

  public func addReminder(title: String, dueDate: Date? = nil, hasTimeComponent: Bool = false) async {
    guard let listID = nudgeListID else { return }
    let draft = ReminderDraft(
      title: title,
      dueDate: dueDate,
      hasTimeComponent: hasTimeComponent,
      listID: listID
    )

    do {
      _ = try await remindersRepository.saveReminder(draft)
      await refresh()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  public func importReminders(ids: [String]) async {
    guard let listID = nudgeListID else { return }
    for id in ids {
      try? await remindersRepository.moveReminder(id: id, to: listID)
    }
    await refresh()
  }

  public func toggleCompletion(for reminder: ReminderItem) async {
    do {
      try await remindersRepository.setCompleted(reminderID: reminder.id, isCompleted: !reminder.isCompleted)
      await refresh()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  public func delete(_ reminder: ReminderItem) async {
    do {
      try await remindersRepository.deleteReminder(id: reminder.id)
      await refresh()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  public func snooze(_ reminder: ReminderItem, minutes: Int) async {
    let date = Date().addingTimeInterval(Double(max(minutes, 1) * 60))
    let draft = ReminderDraft(
      id: reminder.id,
      title: reminder.title,
      notes: reminder.notes,
      dueDate: date,
      hasTimeComponent: true,
      isCompleted: reminder.isCompleted,
      isFlagged: reminder.isFlagged,
      priority: reminder.priority,
      listID: reminder.listID
    )

    do {
      _ = try await remindersRepository.saveReminder(draft)
      await refresh()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  // For the import view
  public func fetchAllReminders() async -> [ReminderItem] {
    do {
      return try await remindersRepository.fetchAllReminders()
    } catch {
      return []
    }
  }

  public func fetchLists() async -> [ReminderList] {
    do {
      return try await remindersRepository.fetchLists()
    } catch {
      return []
    }
  }
}
```

**Step 2: Commit**

```bash
git add NagCorePackage/Sources/NagCore/UI/ReminderListViewModel.swift
git commit -m "refactor: ReminderListViewModel fetches from dedicated Nudge list"
```

---

### Task 9: Create AddReminderView (Due-style)

**Files:**
- Create: `NagCorePackage/Sources/NagCore/UI/AddReminderView.swift`

**Step 1: Create the view**

```swift
import SwiftUI

public struct AddReminderView: View {
  @State private var title = ""
  @State private var dueDate = Date().addingTimeInterval(30 * 60)
  @State private var hasDueDate = true
  @State private var hasTimeComponent = true

  private let onAdd: (String, Date?, Bool) -> Void
  private let onCancel: () -> Void

  public init(
    onAdd: @escaping (String, Date?, Bool) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.onAdd = onAdd
    self.onCancel = onCancel
  }

  public var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("What needs doing?", text: $title)
            .font(.title3)
        }

        Section {
          Toggle("Due date", isOn: $hasDueDate)

          if hasDueDate {
            Toggle("Include time", isOn: $hasTimeComponent)

            if hasTimeComponent {
              DatePicker("When", selection: $dueDate)
            } else {
              DatePicker("When", selection: $dueDate, displayedComponents: .date)
            }
          }
        }
      }
      .navigationTitle("New Reminder")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onCancel)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Add") {
            let date = hasDueDate ? dueDate : nil
            onAdd(title.trimmingCharacters(in: .whitespacesAndNewlines), date, hasTimeComponent)
          }
          .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
  }
}
```

**Step 2: Commit**

```bash
git add NagCorePackage/Sources/NagCore/UI/AddReminderView.swift
git commit -m "feat: add Due-style AddReminderView"
```

---

### Task 10: Create ImportRemindersView

**Files:**
- Create: `NagCorePackage/Sources/NagCore/UI/ImportRemindersView.swift`

**Step 1: Create the view**

```swift
import SwiftUI

public struct ImportRemindersView: View {
  @State private var lists: [ReminderList] = []
  @State private var remindersByList: [String: [ReminderItem]] = [:]
  @State private var selectedIDs: Set<String> = []
  @State private var expandedListIDs: Set<String> = []
  @State private var isLoading = true

  private let nudgeListID: String
  private let fetchLists: () async -> [ReminderList]
  private let fetchAllReminders: () async -> [ReminderItem]
  private let onImport: ([String]) -> Void
  private let onCancel: () -> Void

  public init(
    nudgeListID: String,
    fetchLists: @escaping () async -> [ReminderList],
    fetchAllReminders: @escaping () async -> [ReminderItem],
    onImport: @escaping ([String]) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.nudgeListID = nudgeListID
    self.fetchLists = fetchLists
    self.fetchAllReminders = fetchAllReminders
    self.onImport = onImport
    self.onCancel = onCancel
  }

  public var body: some View {
    NavigationStack {
      Group {
        if isLoading {
          ProgressView()
        } else if lists.isEmpty {
          ContentUnavailableView("No Other Lists", systemImage: "list.bullet", description: Text("All your reminders are in Nudge."))
        } else {
          List {
            ForEach(lists) { list in
              Section(isExpanded: Binding(
                get: { expandedListIDs.contains(list.id) },
                set: { expanded in
                  if expanded { expandedListIDs.insert(list.id) } else { expandedListIDs.remove(list.id) }
                }
              )) {
                ForEach(remindersByList[list.id] ?? []) { reminder in
                  Button {
                    if selectedIDs.contains(reminder.id) {
                      selectedIDs.remove(reminder.id)
                    } else {
                      selectedIDs.insert(reminder.id)
                    }
                  } label: {
                    HStack {
                      Image(systemName: selectedIDs.contains(reminder.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selectedIDs.contains(reminder.id) ? .blue : .secondary)
                      VStack(alignment: .leading) {
                        Text(reminder.title)
                        if let dueDate = reminder.dueDate {
                          Text(dueDate, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                      }
                    }
                  }
                  .tint(.primary)
                }
              } header: {
                Text(list.title)
              }
            }
          }
        }
      }
      .navigationTitle("Import Reminders")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onCancel)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Import (\(selectedIDs.count))") {
            onImport(Array(selectedIDs))
          }
          .disabled(selectedIDs.isEmpty)
        }
      }
      .task {
        let allLists = await fetchLists()
        let allReminders = await fetchAllReminders()

        lists = allLists.filter { $0.id != nudgeListID }
        remindersByList = Dictionary(grouping: allReminders.filter { $0.listID != nudgeListID }, by: \.listID)
        expandedListIDs = Set(lists.map(\.id))
        isLoading = false
      }
    }
  }
}
```

**Step 2: Commit**

```bash
git add NagCorePackage/Sources/NagCore/UI/ImportRemindersView.swift
git commit -m "feat: add ImportRemindersView for moving reminders into Nudge list"
```

---

### Task 11: Create InlineNagSettingsView

**Files:**
- Create: `NagCorePackage/Sources/NagCore/UI/InlineNagSettingsView.swift`

**Step 1: Create the view**

```swift
import SwiftUI

public struct InlineNagSettingsView: View {
  @Binding var policy: NagPolicy

  public init(policy: Binding<NagPolicy>) {
    _policy = policy
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Toggle("Nag enabled", isOn: $policy.isEnabled)

      if policy.isEnabled {
        Stepper(value: $policy.intervalMinutes, in: 1...120) {
          Text("Every \(policy.intervalMinutes) min")
            .font(.subheadline)
        }

        Toggle("Escalate", isOn: Binding(
          get: { policy.escalationAfterNags != nil },
          set: { policy.escalationAfterNags = $0 ? 5 : nil; policy.escalationIntervalMinutes = $0 ? 2 : nil }
        ))

        if policy.escalationAfterNags != nil {
          Stepper(value: Binding(
            get: { policy.escalationAfterNags ?? 5 },
            set: { policy.escalationAfterNags = $0 }
          ), in: 1...50) {
            Text("After \(policy.escalationAfterNags ?? 5) nags")
              .font(.subheadline)
          }

          Stepper(value: Binding(
            get: { policy.escalationIntervalMinutes ?? 2 },
            set: { policy.escalationIntervalMinutes = $0 }
          ), in: 1...60) {
            Text("Then every \(policy.escalationIntervalMinutes ?? 2) min")
              .font(.subheadline)
          }
        }
      }
    }
    .padding(.vertical, 4)
    .font(.subheadline)
  }
}
```

**Step 2: Commit**

```bash
git add NagCorePackage/Sources/NagCore/UI/InlineNagSettingsView.swift
git commit -m "feat: add InlineNagSettingsView for per-reminder tap-to-expand settings"
```

---

### Task 12: Update ReminderRowView for tap-to-expand

**Files:**
- Modify: `NagCorePackage/Sources/NagCore/UI/ReminderRowView.swift`

**Step 1: Add expanded state and inline settings**

Replace the entire file:

```swift
import SwiftUI

public struct ReminderRowView: View {
  private let reminder: ReminderItem
  private let isNagging: Bool
  @Binding private var policy: NagPolicy
  private let isExpanded: Bool
  private let onToggleComplete: () -> Void
  private let onQuickSnooze: () -> Void
  private let onTap: () -> Void
  private let onSavePolicy: () -> Void

  public init(
    reminder: ReminderItem,
    isNagging: Bool,
    policy: Binding<NagPolicy>,
    isExpanded: Bool,
    onToggleComplete: @escaping () -> Void,
    onQuickSnooze: @escaping () -> Void,
    onTap: @escaping () -> Void,
    onSavePolicy: @escaping () -> Void
  ) {
    self.reminder = reminder
    self.isNagging = isNagging
    _policy = policy
    self.isExpanded = isExpanded
    self.onToggleComplete = onToggleComplete
    self.onQuickSnooze = onQuickSnooze
    self.onTap = onTap
    self.onSavePolicy = onSavePolicy
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 12) {
        Button(action: onToggleComplete) {
          Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
            .imageScale(.large)
        }
        .buttonStyle(.plain)

        VStack(alignment: .leading, spacing: 6) {
          Text(reminder.title)
            .font(.headline)
            .foregroundStyle(reminder.isCompleted ? .secondary : .primary)
            .strikethrough(reminder.isCompleted, pattern: .solid)

          if let notes = reminder.notes, !notes.isEmpty {
            Text(notes)
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .lineLimit(2)
          }

          if let dueDate = reminder.dueDate {
            Text(dueDate, style: .relative)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        Spacer(minLength: 0)

        Image(systemName: isNagging ? "bell.fill" : "bell.slash")
          .foregroundStyle(isNagging ? .orange : .secondary)
      }
      .padding(.vertical, 4)
      .contentShape(Rectangle())
      .onTapGesture(perform: onTap)

      if isExpanded {
        Divider()
          .padding(.vertical, 4)

        InlineNagSettingsView(policy: $policy)
          .onChange(of: policy) { _, _ in onSavePolicy() }

        Button("Snooze", action: onQuickSnooze)
          .buttonStyle(.bordered)
          .font(.caption)
          .padding(.top, 4)
      }
    }
  }
}
```

**Step 2: Commit**

```bash
git add NagCorePackage/Sources/NagCore/UI/ReminderRowView.swift
git commit -m "feat: ReminderRowView with tap-to-expand inline nag settings"
```

---

### Task 13: Update ReminderListView for new row API

**Files:**
- Modify: `NagCorePackage/Sources/NagCore/UI/ReminderListView.swift`

**Step 1: Update to work with new ReminderRowView**

Replace the entire file:

```swift
import SwiftUI

public struct ReminderListView: View {
  private let reminders: [ReminderItem]
  private let nagStates: [String: Bool]
  @Binding private var policies: [String: NagPolicy]
  private let globalPolicy: NagPolicy
  @Binding private var expandedReminderID: String?
  private let onToggleCompletion: (ReminderItem) -> Void
  private let onQuickSnooze: (ReminderItem) -> Void
  private let onDelete: (ReminderItem) -> Void
  private let onSavePolicy: (ReminderItem) -> Void

  public init(
    reminders: [ReminderItem],
    nagStates: [String: Bool],
    policies: Binding<[String: NagPolicy]>,
    globalPolicy: NagPolicy,
    expandedReminderID: Binding<String?>,
    onToggleCompletion: @escaping (ReminderItem) -> Void,
    onQuickSnooze: @escaping (ReminderItem) -> Void,
    onDelete: @escaping (ReminderItem) -> Void,
    onSavePolicy: @escaping (ReminderItem) -> Void
  ) {
    self.reminders = reminders
    self.nagStates = nagStates
    _policies = policies
    self.globalPolicy = globalPolicy
    _expandedReminderID = expandedReminderID
    self.onToggleCompletion = onToggleCompletion
    self.onQuickSnooze = onQuickSnooze
    self.onDelete = onDelete
    self.onSavePolicy = onSavePolicy
  }

  public var body: some View {
    List {
      ForEach(reminders) { reminder in
        ReminderRowView(
          reminder: reminder,
          isNagging: nagStates[reminder.id] ?? true,
          policy: Binding(
            get: { policies[reminder.id] ?? globalPolicy },
            set: { policies[reminder.id] = $0 }
          ),
          isExpanded: expandedReminderID == reminder.id,
          onToggleComplete: { onToggleCompletion(reminder) },
          onQuickSnooze: { onQuickSnooze(reminder) },
          onTap: {
            withAnimation {
              expandedReminderID = expandedReminderID == reminder.id ? nil : reminder.id
            }
          },
          onSavePolicy: { onSavePolicy(reminder) }
        )
        .swipeActions(allowsFullSwipe: true) {
          Button(role: .destructive) {
            onDelete(reminder)
          } label: {
            Label("Delete", systemImage: "trash")
          }

          Button {
            onQuickSnooze(reminder)
          } label: {
            Label("Snooze", systemImage: "clock")
          }
          .tint(.blue)
        }
      }
    }
  }
}
```

**Step 2: Commit**

```bash
git add NagCorePackage/Sources/NagCore/UI/ReminderListView.swift
git commit -m "refactor: ReminderListView uses new expandable row API"
```

---

### Task 14: Simplify PolicySettingsView (global settings only)

**Files:**
- Modify: `NagCorePackage/Sources/NagCore/UI/PolicySettingsView.swift`

**Step 1: Remove NagMode picker and list selector**

Replace the entire file:

```swift
import SwiftUI

public struct PolicySettingsView: View {
  @Binding private var policy: NagPolicy

  public init(policy: Binding<NagPolicy>) {
    _policy = policy
  }

  public var body: some View {
    Form {
      Section("Default Nag Settings") {
        Stepper(value: $policy.intervalMinutes, in: 1...120) {
          Text("Interval: \(policy.intervalMinutes) min")
        }

        Stepper(value: $policy.repeatAtLeast, in: 1...100) {
          Text("Repeat At Least: \(policy.repeatAtLeast)")
        }

        Picker("Repeat Mode", selection: $policy.repeatIndefinitelyMode) {
          Text("Off").tag(RepeatIndefinitelyMode.off)
          Text("When Possible").tag(RepeatIndefinitelyMode.whenPossible)
          Text("Always").tag(RepeatIndefinitelyMode.always)
        }
      }

      Section("Escalation Defaults") {
        Toggle("Enable Escalation", isOn: Binding(
          get: { policy.escalationAfterNags != nil },
          set: { policy.escalationAfterNags = $0 ? 5 : nil; policy.escalationIntervalMinutes = $0 ? 2 : nil }
        ))

        if let _ = policy.escalationAfterNags {
          Stepper(value: Binding(
            get: { policy.escalationAfterNags ?? 5 },
            set: { policy.escalationAfterNags = $0 }
          ), in: 1...50) {
            Text("After \(policy.escalationAfterNags ?? 5) nags")
          }

          Stepper(value: Binding(
            get: { policy.escalationIntervalMinutes ?? 2 },
            set: { policy.escalationIntervalMinutes = $0 }
          ), in: 1...60) {
            Text("Escalated interval: \(policy.escalationIntervalMinutes ?? 2) min")
          }
        }
      }

      Section("Date-only Due Items") {
        Stepper(value: $policy.dateOnlyDueHour, in: 0...23) {
          Text("Treat date-only reminders as due at \(policy.dateOnlyDueHour):00")
        }
      }
    }
    .formStyle(.grouped)
  }
}
```

**Step 2: Commit**

```bash
git add NagCorePackage/Sources/NagCore/UI/PolicySettingsView.swift
git commit -m "refactor: simplify PolicySettingsView, remove NagMode and list selector"
```

---

### Task 15: Update ReminderDashboardView

**Files:**
- Modify: `NagCorePackage/Sources/NagCore/UI/ReminderDashboardView.swift`

**Step 1: Replace with new dashboard**

Replace the entire file. Key changes: remove segmented picker, add toolbar buttons for Add/Import/Settings, wire up new ReminderListView API, manage per-reminder policies and expanded state.

```swift
import SwiftUI

public struct ReminderDashboardView: View {
  @StateObject private var viewModel: ReminderListViewModel
  @EnvironmentObject private var appController: NagAppController
  @State private var quickSnoozeReminder: ReminderItem?
  @State private var showSettings = false
  @State private var showAddReminder = false
  @State private var showImport = false
  @State private var expandedReminderID: String?
  @State private var reminderPolicies: [String: NagPolicy] = [:]

  private let debugNotificationsEnabled: Bool

  public init(
    repository: (any RemindersRepository)? = nil,
    policyStore: (any NagPolicyStore)? = nil
  ) {
    _viewModel = StateObject(
      wrappedValue: ReminderListViewModel(
        remindersRepository: repository ?? MockRemindersRepository.sampleData(),
        policyStore: policyStore
      )
    )

    debugNotificationsEnabled = ProcessInfo.processInfo.arguments.contains("--ui-test-debug-notifications")
  }

  public var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        if let errorMessage = viewModel.errorMessage {
          Text(errorMessage)
            .font(.footnote)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
        }

        ReminderListView(
          reminders: viewModel.visibleReminders,
          nagStates: viewModel.nagStates,
          policies: $reminderPolicies,
          globalPolicy: viewModel.nagPolicy,
          expandedReminderID: $expandedReminderID,
          onToggleCompletion: { reminder in
            Task {
              await appController.markDone(reminderID: reminder.id)
              await viewModel.refresh()
            }
          },
          onQuickSnooze: { reminder in
            quickSnoozeReminder = reminder
          },
          onDelete: { reminder in
            Task { await viewModel.delete(reminder) }
          },
          onSavePolicy: { reminder in
            if let policy = reminderPolicies[reminder.id] {
              try? viewModel.policyStoreForSaving?.save(policy, for: reminder.id)
              viewModel.loadNagStates()
            }
          }
        )
      }
      .searchable(text: $viewModel.searchText)
      .navigationTitle("Nudge")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button {
            showAddReminder = true
          } label: {
            Image(systemName: "plus")
          }
        }
        ToolbarItem {
          Button {
            showImport = true
          } label: {
            Image(systemName: "square.and.arrow.down")
          }
        }
        ToolbarItem {
          Button {
            showSettings = true
          } label: {
            Image(systemName: "gearshape")
          }
        }
      }
      .overlay {
        if viewModel.isLoading {
          ProgressView()
        }
      }
      .task {
        await viewModel.refresh()
        loadPolicies()
      }
      .sheet(item: $quickSnoozeReminder) { reminder in
        QuickSnoozeView(
          title: reminder.title,
          presets: viewModel.nagPolicy.snoozePresetMinutes,
          onSnooze: { minutes in
            Task {
              await appController.snooze(reminderID: reminder.id, minutes: minutes)
              await viewModel.refresh()
            }
            quickSnoozeReminder = nil
          },
          onMarkDone: {
            Task {
              await appController.markDone(reminderID: reminder.id)
              await viewModel.refresh()
            }
            quickSnoozeReminder = nil
          },
          onStopNagging: {
            Task {
              await appController.stopNagging(reminderID: reminder.id)
              await viewModel.refresh()
            }
            quickSnoozeReminder = nil
          }
        )
      }
      .sheet(isPresented: $showSettings) {
        NavigationStack {
          PolicySettingsView(policy: $viewModel.nagPolicy)
            .navigationTitle("Nag Settings")
            .toolbar {
              ToolbarItem {
                Button("Done") {
                  viewModel.savePolicy()
                  showSettings = false
                }
              }
            }
        }
      }
      .sheet(isPresented: $showAddReminder) {
        AddReminderView(
          onAdd: { title, dueDate, hasTime in
            Task {
              await viewModel.addReminder(title: title, dueDate: dueDate, hasTimeComponent: hasTime)
            }
            showAddReminder = false
          },
          onCancel: {
            showAddReminder = false
          }
        )
      }
      .sheet(isPresented: $showImport) {
        if let nudgeListID = viewModel.nudgeListID {
          ImportRemindersView(
            nudgeListID: nudgeListID,
            fetchLists: { await viewModel.fetchLists() },
            fetchAllReminders: { await viewModel.fetchAllReminders() },
            onImport: { ids in
              Task { await viewModel.importReminders(ids: ids) }
              showImport = false
            },
            onCancel: { showImport = false }
          )
        }
      }
      #if os(iOS)
      .fullScreenCover(isPresented: Binding(
        get: { appController.nagScreenReminderID != nil },
        set: { if !$0 { appController.dismissNagScreen() } }
      )) {
        nagScreenContent
      }
      #else
      .sheet(isPresented: Binding(
        get: { appController.nagScreenReminderID != nil },
        set: { if !$0 { appController.dismissNagScreen() } }
      )) {
        nagScreenContent
      }
      #endif
      .safeAreaInset(edge: .bottom) {
        if debugNotificationsEnabled {
          debugPanel
        }
      }
    }
  }

  private func loadPolicies() {
    // Stub — policies loaded on demand via ReminderListView bindings
  }

  @ViewBuilder
  private var nagScreenContent: some View {
    if let reminderID = appController.nagScreenReminderID,
       let reminder = viewModel.reminders.first(where: { $0.id == reminderID }) {
      NagScreenView(
        title: reminder.title,
        snoozePresets: viewModel.nagPolicy.snoozePresetMinutes,
        onSnooze: { minutes in
          Task {
            await appController.snooze(reminderID: reminderID, minutes: minutes)
            await viewModel.refresh()
          }
          appController.dismissNagScreen()
        },
        onMarkDone: {
          Task {
            await appController.markDone(reminderID: reminderID)
            await viewModel.refresh()
          }
          appController.dismissNagScreen()
        },
        onStop: {
          Task {
            await appController.stopNagging(reminderID: reminderID)
            await viewModel.refresh()
          }
          appController.dismissNagScreen()
        }
      )
    } else {
      NagScreenView(
        title: "Reminder",
        onSnooze: { _ in appController.dismissNagScreen() },
        onStop: { appController.dismissNagScreen() }
      )
    }
  }

  private var debugPanel: some View {
    HStack(spacing: 12) {
      Button("Simulate Nag") {
        if let first = viewModel.visibleReminders.first {
          appController.handle(url: DeepLinkFactory.nagScreenURL(reminderID: first.id))
        }
      }
      .buttonStyle(.borderedProminent)
      .accessibilityIdentifier("debug.simulateNagDelivery")

      Button("Simulate Action") {
        quickSnoozeReminder = viewModel.visibleReminders.first ?? ReminderItem(
          id: "debug-reminder",
          title: "Debug Reminder",
          notes: nil,
          dueDate: Date(),
          isCompleted: false,
          isFlagged: false,
          priority: 0,
          listID: "debug",
          listTitle: "Debug",
          hasTimeComponent: true
        )
      }
      .buttonStyle(.bordered)
      .accessibilityIdentifier("debug.simulateNotificationAction")
    }
    .padding(.horizontal)
    .padding(.bottom, 8)
  }
}
```

Note: The dashboard references `viewModel.policyStoreForSaving` which doesn't exist yet. We need to expose the policy store from the view model for the `onSavePolicy` callback. Add this computed property to `ReminderListViewModel`:

```swift
  public var policyStoreForSaving: (any NagPolicyStore)? { policyStore }
```

**Step 2: Commit**

```bash
git add NagCorePackage/Sources/NagCore/UI/ReminderDashboardView.swift NagCorePackage/Sources/NagCore/UI/ReminderListViewModel.swift
git commit -m "feat: update ReminderDashboardView with add, import, and inline settings"
```

---

### Task 16: Build and fix compilation errors

**Step 1: Build the package**

Run: `swift build --package-path NagCorePackage 2>&1`

Expect possible compilation errors from:
- Leftover `NagMode` references in test stubs
- The `PolicySettingsView` `lists` parameter removal (was `init(policy:lists:)`, now `init(policy:)`)
- Any missed `SmartList` references

**Step 2: Fix all compilation errors**

Address each error. Common fixes:
- Remove `lists:` parameter from any `PolicySettingsView` call sites
- Remove `nagMode:` and `nagEnabledListIDs:` from any `NagPolicy(...)` construction in tests
- Update test helper stubs

**Step 3: Run tests**

Run: `swift test --package-path NagCorePackage`
Expected: All tests pass

**Step 4: Commit**

```bash
git add -A
git commit -m "fix: resolve compilation errors from dedicated list migration"
```

---

### Task 17: Final verification

**Step 1: Build package**

Run: `swift build --package-path NagCorePackage`
Expected: Build succeeds

**Step 2: Run full test suite**

Run: `swift test --package-path NagCorePackage`
Expected: All tests pass (should be ~15 tests — we removed 2 mode-based tests)

**Step 3: Verify no stale references**

Search for any remaining references to removed types:
- `SmartList`
- `NagMode`
- `nagEnabledListIDs`
- `filtered(for:`
- `fetchReminders(in:`

None should remain in source code (may still appear in design docs, which is fine).
