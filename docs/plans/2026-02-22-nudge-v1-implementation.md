# Nudge v1 Completion — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make Nudge a fully functional ADHD nag layer on Apple Reminders — fix the broken nag loop, add per-reminder/per-list nag modes, wire deep-link navigation, persist policy, and strip features that don't serve the nag-layer use case.

**Architecture:** Fix-the-pipes approach. The existing architecture (protocol-driven dependencies, pure scheduler, engine orchestration) is sound. All changes are wiring fixes, model additions, and UI plumbing. No rewrites.

**Tech Stack:** Swift 5.10, SwiftUI, SwiftData, EventKit, UserNotifications, XCTest

---

## Task 1: Fix Nag Count Tracking

Nag count is never incremented, which breaks escalation. The scheduler already checks `nagCount` in `resolvedInterval()` — we just need the engine to increment it after scheduling.

**Files:**
- Modify: `NagCorePackage/Sources/NagCore/Notifications/NagEngine.swift`
- Test: `NagCorePackage/Tests/NagCoreTests/NagEngineTests.swift`

### Step 1: Write failing test — nag count increments after scheduling

Add to `NagEngineTests.swift`:

```swift
func testReplenishScheduleIncrementsNagCount() async throws {
    let now = Date(timeIntervalSince1970: 1_700_100_000)
    let reminder = ReminderItem(
        id: "r1",
        title: "Water plants",
        notes: nil,
        dueDate: now.addingTimeInterval(-300),
        isCompleted: false,
        isFlagged: false,
        priority: 0,
        listID: "list-1",
        listTitle: "Home",
        hasTimeComponent: true
    )

    let remindersRepository = MockRemindersRepository(reminders: [reminder])
    let sessionStore = InMemoryNagSessionStore()
    let notificationClient = MockNotificationClient()
    let policyStore = StubNagPolicyStore()

    let engine = NagEngine(
        remindersRepository: remindersRepository,
        policyStore: policyStore,
        sessionStore: sessionStore,
        notificationClient: notificationClient
    )

    _ = try await engine.replenishSchedule(now: now, perSessionCap: 3, globalCap: 10)

    let session = sessionStore.session(for: "r1")!
    XCTAssertEqual(session.nagCount, 3, "nagCount should equal number of scheduled nags")
    XCTAssertNotNil(session.lastNagAt, "lastNagAt should be set after scheduling")
}
```

### Step 2: Run test to verify it fails

Run: `swift test --package-path NagCorePackage --filter testReplenishScheduleIncrementsNagCount`
Expected: FAIL — `session.nagCount` is 0

### Step 3: Implement nag count update in engine

In `NagEngine.swift`, replace `replenishSchedule` method. After building the decision and before saving sessions, update nag counts based on scheduled nags:

```swift
@discardableResult
public func replenishSchedule(
    now: Date = Date(),
    perSessionCap: Int = 5,
    globalCap: Int = 40
) async throws -> NagScheduleDecision {
    let reminders = try await remindersRepository.fetchReminders(in: .all)
    let existingSessions = sessionStore.allSessions()

    let decision = scheduler.buildSchedule(
        reminders: reminders,
        existingSessions: existingSessions,
        policies: policyStore.allPoliciesByReminderID(),
        globalPolicy: policyStore.globalPolicy(),
        now: now,
        perSessionCap: perSessionCap,
        globalCap: globalCap
    )

    // Update nag counts based on what was actually scheduled (after global cap)
    let scheduledByReminder = Dictionary(grouping: decision.scheduled, by: \.reminderID)

    var startedSessions = decision.startedSessions
    for i in startedSessions.indices {
        let count = scheduledByReminder[startedSessions[i].reminderID]?.count ?? 0
        startedSessions[i].nagCount += count
        if count > 0 { startedSessions[i].lastNagAt = now }
    }

    var updatedSessions = decision.updatedSessions
    for i in updatedSessions.indices {
        let count = scheduledByReminder[updatedSessions[i].reminderID]?.count ?? 0
        updatedSessions[i].nagCount += count
        if count > 0 { updatedSessions[i].lastNagAt = now }
    }

    try sessionStore.save(startedSessions)
    try sessionStore.save(updatedSessions)
    for reminderID in decision.stoppedSessionIDs {
        try sessionStore.stopSession(reminderID: reminderID, at: now)
    }

    await notificationClient.registerNotificationCategories()

    let pendingIDs = Set(await notificationClient.pendingRequestIDs())
    let desiredIDs = Set(decision.scheduled.map(\.identifier))

    var removals = pendingIDs.subtracting(desiredIDs)
    for reminderID in decision.stoppedSessionIDs {
        for pendingID in pendingIDs where pendingID.hasPrefix("nag.\(reminderID).") {
            removals.insert(pendingID)
        }
    }

    if !removals.isEmpty {
        await notificationClient.removePendingRequests(withIDs: Array(removals))
    }

    try await notificationClient.schedule(decision.scheduled)
    return decision
}
```

### Step 4: Run test to verify it passes

Run: `swift test --package-path NagCorePackage --filter testReplenishScheduleIncrementsNagCount`
Expected: PASS

### Step 5: Write failing test — escalation uses shorter interval after threshold

Add to `NagSchedulerTests.swift`:

```swift
func testEscalationUsesShortIntervalAfterNagCountThreshold() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let reminder = ReminderItem(
        id: "r1",
        title: "Take medications",
        notes: nil,
        dueDate: now.addingTimeInterval(-300),
        isCompleted: false,
        isFlagged: false,
        priority: 0,
        listID: "list-1",
        listTitle: "Reminders",
        hasTimeComponent: true
    )

    let escalatingPolicy = NagPolicy(
        isEnabled: true,
        intervalMinutes: 10,
        escalationAfterNags: 3,
        escalationIntervalMinutes: 2
    )

    // Session with nagCount below threshold — should use normal interval
    let belowThreshold = NagSession(
        reminderID: "r1",
        reminderTitle: "Take medications",
        listTitle: "Reminders",
        dueDate: now.addingTimeInterval(-300),
        policyEnabled: true,
        intervalMinutes: 10,
        nagCount: 2,
        snoozeUntil: nil,
        lastNagAt: nil,
        stoppedAt: nil,
        nextEligibleAt: nil
    )

    let scheduler = NagScheduler()
    let normalDecision = scheduler.buildSchedule(
        reminders: [reminder],
        existingSessions: [belowThreshold],
        policies: [:],
        globalPolicy: escalatingPolicy,
        now: now,
        perSessionCap: 2
    )

    // Verify normal 10-min intervals
    XCTAssertEqual(normalDecision.scheduled.count, 2)
    if normalDecision.scheduled.count == 2 {
        let gap = normalDecision.scheduled[1].fireDate.timeIntervalSince(normalDecision.scheduled[0].fireDate)
        XCTAssertEqual(gap, 600, accuracy: 1, "Should use 10-min interval below threshold")
    }

    // Session with nagCount at threshold — should use escalated interval
    let atThreshold = NagSession(
        reminderID: "r1",
        reminderTitle: "Take medications",
        listTitle: "Reminders",
        dueDate: now.addingTimeInterval(-300),
        policyEnabled: true,
        intervalMinutes: 10,
        nagCount: 3,
        snoozeUntil: nil,
        lastNagAt: nil,
        stoppedAt: nil,
        nextEligibleAt: nil
    )

    let escalatedDecision = scheduler.buildSchedule(
        reminders: [reminder],
        existingSessions: [atThreshold],
        policies: [:],
        globalPolicy: escalatingPolicy,
        now: now,
        perSessionCap: 2
    )

    // Verify escalated 2-min intervals
    XCTAssertEqual(escalatedDecision.scheduled.count, 2)
    if escalatedDecision.scheduled.count == 2 {
        let gap = escalatedDecision.scheduled[1].fireDate.timeIntervalSince(escalatedDecision.scheduled[0].fireDate)
        XCTAssertEqual(gap, 120, accuracy: 1, "Should use 2-min interval at/above threshold")
    }
}
```

### Step 6: Run test to verify it passes (escalation logic already exists in `resolvedInterval`)

Run: `swift test --package-path NagCorePackage --filter testEscalationUsesShortIntervalAfterNagCountThreshold`
Expected: PASS (the `resolvedInterval` method already handles this — the test confirms it works with real data)

### Step 7: Run all existing tests to verify no regressions

Run: `swift test --package-path NagCorePackage`
Expected: All tests pass

### Step 8: Commit

```bash
git add NagCorePackage/Sources/NagCore/Notifications/NagEngine.swift NagCorePackage/Tests/NagCoreTests/NagEngineTests.swift NagCorePackage/Tests/NagCoreTests/NagSchedulerTests.swift
git commit -m "fix: increment nag count after scheduling, verify escalation"
```

---

## Task 2: Add NagMode (Per-Reminder / Per-List)

Add a `NagMode` enum so users choose between opting in individual reminders or entire lists. Update the scheduler to check the mode when deciding which reminders to nag.

**Files:**
- Modify: `NagCorePackage/Sources/NagCore/Models/NagPolicy.swift`
- Modify: `NagCorePackage/Sources/NagCore/Persistence/NagPolicyStore.swift`
- Modify: `NagCorePackage/Sources/NagCore/Notifications/NagScheduler.swift`
- Test: `NagCorePackage/Tests/NagCoreTests/NagSchedulerTests.swift`
- Modify: `NagCorePackage/Tests/NagCoreTests/NagEngineTests.swift` (update StubNagPolicyStore)

### Step 1: Add NagMode enum and new fields to NagPolicy

In `NagPolicy.swift`, add the enum before `NagPolicy` struct and add two new fields:

```swift
public enum NagMode: String, CaseIterable, Codable, Sendable {
    case perReminder
    case perList
}
```

Add to `NagPolicy` struct (new fields):
```swift
public var nagMode: NagMode
public var nagEnabledListIDs: Set<String>
```

Add to `NagPolicy.init()` with defaults:
```swift
nagMode: NagMode = .perList,
nagEnabledListIDs: Set<String> = [],
```

Update `NagPolicy.default` — it uses the memberwise init, so defaults apply automatically.

### Step 2: Add fields to NagPolicyRecord and update SwiftDataNagPolicyStore

In `NagPolicyStore.swift`, add to `NagPolicyRecord`:

```swift
public var nagModeRaw: String = "perList"
public var nagEnabledListIDsRaw: String = ""
```

Add corresponding parameters to `NagPolicyRecord.init()`:
```swift
nagModeRaw: String = "perList",
nagEnabledListIDsRaw: String = ""
```

In `SwiftDataNagPolicyStore`, update `apply(policy:to:)`:
```swift
record.nagModeRaw = policy.nagMode.rawValue
record.nagEnabledListIDsRaw = policy.nagEnabledListIDs.sorted().joined(separator: ",")
```

Update `decode(record:)` to include:
```swift
nagMode: NagMode(rawValue: record.nagModeRaw) ?? .perList,
nagEnabledListIDs: Set(record.nagEnabledListIDsRaw.split(separator: ",").map(String.init))
```

Also update the `NagPolicyRecord(...)` creation in `save(_:for:)` to pass the new fields:
```swift
nagModeRaw: policy.nagMode.rawValue,
nagEnabledListIDsRaw: policy.nagEnabledListIDs.sorted().joined(separator: ",")
```

### Step 3: Build to verify model changes compile

Run: `swift build --package-path NagCorePackage`
Expected: Build succeeds (existing code uses `policy.isEnabled` which still exists)

### Step 4: Write failing test — perReminder mode only nags opted-in reminders

Add to `NagSchedulerTests.swift`:

```swift
func testPerReminderModeOnlyNagsOptedInReminders() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let opted = ReminderItem(
        id: "r1", title: "Opted In", notes: nil,
        dueDate: now.addingTimeInterval(-300), isCompleted: false,
        isFlagged: false, priority: 0,
        listID: "list-1", listTitle: "Work", hasTimeComponent: true
    )
    let notOpted = ReminderItem(
        id: "r2", title: "Not Opted In", notes: nil,
        dueDate: now.addingTimeInterval(-300), isCompleted: false,
        isFlagged: false, priority: 0,
        listID: "list-1", listTitle: "Work", hasTimeComponent: true
    )

    let globalPolicy = NagPolicy(isEnabled: true, nagMode: .perReminder)
    let perReminder: [String: NagPolicy] = [
        "r1": NagPolicy(isEnabled: true)
    ]

    let scheduler = NagScheduler()
    let decision = scheduler.buildSchedule(
        reminders: [opted, notOpted],
        existingSessions: [],
        policies: perReminder,
        globalPolicy: globalPolicy,
        now: now,
        perSessionCap: 1
    )

    XCTAssertEqual(decision.startedSessions.count, 1)
    XCTAssertEqual(decision.startedSessions.first?.reminderID, "r1")
    XCTAssertTrue(decision.scheduled.allSatisfy { $0.reminderID == "r1" })
}
```

### Step 5: Run test to verify it fails

Run: `swift test --package-path NagCorePackage --filter testPerReminderModeOnlyNagsOptedInReminders`
Expected: FAIL — both reminders get nagged because the scheduler doesn't check nagMode

### Step 6: Write failing test — perList mode nags all reminders in enabled lists

```swift
func testPerListModeNagsRemindersInEnabledLists() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let inEnabledList = ReminderItem(
        id: "r1", title: "Work Task", notes: nil,
        dueDate: now.addingTimeInterval(-300), isCompleted: false,
        isFlagged: false, priority: 0,
        listID: "work", listTitle: "Work", hasTimeComponent: true
    )
    let inDisabledList = ReminderItem(
        id: "r2", title: "Home Task", notes: nil,
        dueDate: now.addingTimeInterval(-300), isCompleted: false,
        isFlagged: false, priority: 0,
        listID: "home", listTitle: "Home", hasTimeComponent: true
    )

    let globalPolicy = NagPolicy(
        isEnabled: true,
        nagMode: .perList,
        nagEnabledListIDs: ["work"]
    )

    let scheduler = NagScheduler()
    let decision = scheduler.buildSchedule(
        reminders: [inEnabledList, inDisabledList],
        existingSessions: [],
        policies: [:],
        globalPolicy: globalPolicy,
        now: now,
        perSessionCap: 1
    )

    XCTAssertEqual(decision.startedSessions.count, 1)
    XCTAssertEqual(decision.startedSessions.first?.reminderID, "r1")
}
```

### Step 7: Update scheduler to check NagMode

In `NagScheduler.swift`, replace the section inside the `for reminder in reminders` loop (lines 23-33) where `policy` is resolved and the `guard` checks `policy.isEnabled`:

Replace:
```swift
let policy = policies[reminder.id] ?? globalPolicy
let effectiveDue = effectiveDueDate(for: reminder, policy: policy, now: now)
let priorSession = existingByID[reminder.id]

guard let due = effectiveDue, !reminder.isCompleted, policy.isEnabled, due <= now else {
```

With:
```swift
let perReminderPolicy = policies[reminder.id]
let policy = perReminderPolicy ?? globalPolicy
let effectiveDue = effectiveDueDate(for: reminder, policy: policy, now: now)
let priorSession = existingByID[reminder.id]

let isNagEnabled: Bool
switch globalPolicy.nagMode {
case .perReminder:
    isNagEnabled = perReminderPolicy?.isEnabled ?? false
case .perList:
    isNagEnabled = perReminderPolicy?.isEnabled ?? globalPolicy.nagEnabledListIDs.contains(reminder.listID)
}

guard let due = effectiveDue, !reminder.isCompleted, isNagEnabled, due <= now else {
```

### Step 8: Run the two new tests

Run: `swift test --package-path NagCorePackage --filter "testPerReminderMode|testPerListMode"`
Expected: Both PASS

### Step 9: Run all tests to verify no regressions

Run: `swift test --package-path NagCorePackage`
Expected: All pass. **Note:** Existing tests use `globalPolicy: .default` which has `nagMode: .perList` and empty `nagEnabledListIDs`. These tests pass because they DON'T use per-reminder policies, so the `guard` will fail and reminders won't be nagged... wait. Let me check.

The existing `testStartSessionWhenOverdue` test passes `globalPolicy: .default` with no per-reminder policies. With our change, `nagMode = .perList` and `nagEnabledListIDs = []`. The check becomes: `globalPolicy.nagEnabledListIDs.contains(reminder.listID)` → `[].contains("list-1")` → `false`. The test will FAIL.

**Fix:** Update existing tests that rely on global `isEnabled: true` behavior. We need to either:
(a) Pass a per-reminder policy, or
(b) Pass a globalPolicy with `nagEnabledListIDs` containing the test list ID, or
(c) Set nagMode to perReminder and pass a per-reminder policy.

The simplest fix: update existing scheduler tests to pass a globalPolicy with the test list ID in `nagEnabledListIDs`:

```swift
let globalPolicy = NagPolicy(nagEnabledListIDs: ["list-1"])
```

Update these tests:
- `testStartSessionWhenOverdue` — add `globalPolicy: NagPolicy(nagEnabledListIDs: ["list-1"])`
- `testStopSessionWhenCompleted` — same
- `testPauseAndResumeOnSnoozeUntil` — same
- `testRollingSchedulingRespectsSessionAndGlobalCaps` — same

Also update `StubNagPolicyStore` in `NagEngineTests.swift` to return a policy with nagEnabledListIDs matching the test data:

```swift
@MainActor
private final class StubNagPolicyStore: NagPolicyStore {
    var globalPolicyValue: NagPolicy
    var perReminderPolicies: [String: NagPolicy] = [:]

    init(globalPolicy: NagPolicy = NagPolicy(nagEnabledListIDs: ["list-1"])) {
        self.globalPolicyValue = globalPolicy
    }

    func globalPolicy() -> NagPolicy { globalPolicyValue }
    func policy(for reminderID: String) -> NagPolicy? { perReminderPolicies[reminderID] }
    func allPoliciesByReminderID() -> [String: NagPolicy] { perReminderPolicies }
    func save(_ policy: NagPolicy, for reminderID: String?) throws {
        if let id = reminderID {
            perReminderPolicies[id] = policy
        } else {
            globalPolicyValue = policy
        }
    }
    func deletePolicy(for reminderID: String) throws { perReminderPolicies[reminderID] = nil }
}
```

### Step 10: Run all tests again after fixing test data

Run: `swift test --package-path NagCorePackage`
Expected: All pass

### Step 11: Commit

```bash
git add NagCorePackage/Sources/NagCore/Models/NagPolicy.swift NagCorePackage/Sources/NagCore/Persistence/NagPolicyStore.swift NagCorePackage/Sources/NagCore/Notifications/NagScheduler.swift NagCorePackage/Tests/NagCoreTests/NagSchedulerTests.swift NagCorePackage/Tests/NagCoreTests/NagEngineTests.swift
git commit -m "feat: add NagMode (per-reminder / per-list) with scheduler support"
```

---

## Task 3: Wire Policy Persistence

Settings changes are currently in-memory only. Wire the policy store so changes persist across app restarts.

**Files:**
- Modify: `NagCorePackage/Sources/NagCore/UI/ReminderListViewModel.swift`
- Modify: `NagCorePackage/Sources/NagCore/UI/ReminderDashboardView.swift`
- Modify: `NagCorePackage/Sources/NagCore/UI/PolicySettingsView.swift`
- Modify: `NagCorePackage/Sources/NagCore/NudgeRootView.swift`
- Modify: `Apps/iOS/NudgeIOSApp.swift`

### Step 1: Add policyStore to ReminderListViewModel

In `ReminderListViewModel.swift`, add a `policyStore` dependency and load the global policy on init:

Replace the class declaration and init:

```swift
@MainActor
public final class ReminderListViewModel: ObservableObject {
    @Published public private(set) var reminders: [ReminderItem] = []
    @Published public var selectedSmartList: SmartList = .today
    @Published public var searchText = ""
    @Published public var isLoading = false
    @Published public var errorMessage: String?
    @Published public var nagPolicy: NagPolicy = .default

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
```

Keep all other existing methods unchanged.

### Step 2: Save policy on settings dismiss

In `ReminderDashboardView.swift`, update the settings sheet to save on dismiss. Change the `.sheet(isPresented: $showSettings)` block:

Replace:
```swift
.sheet(isPresented: $showSettings) {
    NavigationStack {
        PolicySettingsView(policy: $viewModel.nagPolicy)
            .navigationTitle("Nag Settings")
            .toolbar {
                ToolbarItem {
                    Button("Done") {
                        showSettings = false
                    }
                }
            }
    }
}
```

With:
```swift
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
```

### Step 3: Thread policyStore through init chain

In `ReminderDashboardView.swift`, update init to accept policyStore:

```swift
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
```

In `NudgeRootView.swift`, update to pass through:

```swift
public struct NudgeRootView: View {
    private let repository: (any RemindersRepository)?
    private let policyStore: (any NagPolicyStore)?

    public init(
        repository: (any RemindersRepository)? = nil,
        policyStore: (any NagPolicyStore)? = nil
    ) {
        self.repository = repository
        self.policyStore = policyStore
    }

    public var body: some View {
        ReminderDashboardView(repository: repository, policyStore: policyStore)
    }
}
```

In `NudgeIOSApp.swift`, expose the policyStore from dependencies and pass it through:

Add `let policyStore: SwiftDataNagPolicyStore` to `IOSAppDependencies` and set it in init (it's already created locally — just store it as a property).

Update the body:
```swift
NudgeRootView(
    repository: dependencies.remindersRepository,
    policyStore: dependencies.policyStore
)
```

### Step 4: Build to verify compilation

Run: `swift build --package-path NagCorePackage`
Expected: Build succeeds

### Step 5: Commit

```bash
git add NagCorePackage/Sources/NagCore/UI/ReminderListViewModel.swift NagCorePackage/Sources/NagCore/UI/ReminderDashboardView.swift NagCorePackage/Sources/NagCore/UI/PolicySettingsView.swift NagCorePackage/Sources/NagCore/NudgeRootView.swift Apps/iOS/NudgeIOSApp.swift
git commit -m "feat: wire policy persistence through settings dismiss"
```

---

## Task 4: Wire Deep-Link Navigation and Action Dispatch

Tapping a notification deep link currently does nothing in the UI. Wire `NagAppController`'s published state to the dashboard, and route all snooze/complete/stop actions through `NagEngine` instead of just updating the due date.

**Files:**
- Modify: `NagCorePackage/Sources/NagCore/UI/ReminderDashboardView.swift`
- Modify: `NagCorePackage/Sources/NagCore/UI/NagScreenView.swift`
- Modify: `NagCorePackage/Sources/NagCore/App/NagAppController.swift`

### Step 1: Add engine reference to NagAppController for public access

In `NagAppController.swift`, the `engine` property is already private. Add a public method for snooze that the dashboard can call without knowing action IDs:

```swift
public func snooze(reminderID: String, minutes: Int) async {
    do {
        try await engine.handleNotificationAction(
            NotificationActionIDs.snooze(minutes: minutes),
            reminderID: reminderID
        )
        try await engine.replenishSchedule()
    } catch {
        lastErrorMessage = error.localizedDescription
    }
}

public func markDone(reminderID: String) async {
    do {
        try await engine.handleNotificationAction(
            NotificationActionIDs.markDone,
            reminderID: reminderID
        )
    } catch {
        lastErrorMessage = error.localizedDescription
    }
}

public func stopNagging(reminderID: String) async {
    do {
        try await engine.handleNotificationAction(
            NotificationActionIDs.stopNagging,
            reminderID: reminderID
        )
    } catch {
        lastErrorMessage = error.localizedDescription
    }
}
```

### Step 2: Update NagScreenView to accept configurable snooze presets

Replace `NagScreenView` to accept snooze presets and a minutes-based callback:

```swift
public struct NagScreenView: View {
    private let title: String
    private let snoozePresets: [Int]
    private let onSnooze: (Int) -> Void
    private let onMarkDone: () -> Void
    private let onStop: () -> Void

    public init(
        title: String,
        snoozePresets: [Int] = [5, 10, 20],
        onSnooze: @escaping (Int) -> Void,
        onMarkDone: @escaping () -> Void = {},
        onStop: @escaping () -> Void
    ) {
        self.title = title
        self.snoozePresets = snoozePresets
        self.onSnooze = onSnooze
        self.onMarkDone = onMarkDone
        self.onStop = onStop
    }

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.red.opacity(0.3), Color.orange.opacity(0.35)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                Text("Overdue")
                    .font(.title3.weight(.semibold))
                    .textCase(.uppercase)
                    .accessibilityIdentifier("nag.screen.title")

                Text(title)
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)

                ForEach(snoozePresets, id: \.self) { minutes in
                    Button("Snooze \(minutes) Minutes") { onSnooze(minutes) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }

                Button("Mark Done", action: onMarkDone)
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                Button("Stop Nagging", role: .destructive, action: onStop)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
            .padding(28)
            .accessibilityIdentifier("nag.screen")
        }
    }
}
```

### Step 3: Wire dashboard to observe NagAppController and dispatch actions through engine

This is the largest change. Rewrite `ReminderDashboardView` to:
- Add `@EnvironmentObject var appController: NagAppController`
- Observe `appController.nagScreenReminderID` for fullScreenCover
- Route snooze/markDone/stop actions through appController
- Remove the addReminder toolbar button (nag layer, not reminders app)

Replace `ReminderDashboardView.swift` body and add the `@EnvironmentObject`:

```swift
public struct ReminderDashboardView: View {
    @StateObject private var viewModel: ReminderListViewModel
    @EnvironmentObject private var appController: NagAppController
    @State private var quickSnoozeReminder: ReminderItem?
    @State private var showSettings = false

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
            VStack(spacing: 12) {
                Picker("Smart List", selection: $viewModel.selectedSmartList) {
                    ForEach(SmartList.allCases) { smartList in
                        Text(smartList.rawValue)
                            .tag(smartList)
                    }
                }
                .pickerStyle(.segmented)

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                ReminderListView(
                    reminders: viewModel.visibleReminders,
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
                    }
                )
            }
            .padding(.horizontal)
            .searchable(text: $viewModel.searchText)
            .navigationTitle("Nudge")
            .toolbar {
                ToolbarItem {
                    Button("Settings") {
                        showSettings = true
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
            }
            .onChange(of: viewModel.selectedSmartList) { _, _ in
                Task { await viewModel.refresh() }
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
            .fullScreenCover(isPresented: Binding(
                get: { appController.nagScreenReminderID != nil },
                set: { if !$0 { appController.dismissNagScreen() } }
            )) {
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
            .safeAreaInset(edge: .bottom) {
                if debugNotificationsEnabled {
                    debugPanel
                }
            }
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

### Step 4: Build to verify compilation

Run: `swift build --package-path NagCorePackage`
Expected: Build succeeds

### Step 5: Commit

```bash
git add NagCorePackage/Sources/NagCore/UI/ReminderDashboardView.swift NagCorePackage/Sources/NagCore/UI/NagScreenView.swift NagCorePackage/Sources/NagCore/App/NagAppController.swift
git commit -m "feat: wire deep-link navigation and route actions through engine"
```

---

## Task 5: Strip Features and Harden Background Refresh

Remove features that don't serve the nag-layer use case. Harden refresh so nags keep coming.

**Files:**
- Modify: `NagCorePackage/Sources/NagCore/UI/PolicySettingsView.swift`
- Modify: `Apps/iOS/NudgeIOSApp.swift`

### Step 1: Remove quiet hours from PolicySettingsView

In `PolicySettingsView.swift`, remove the entire "Quiet Hours" `Section`. Keep only "Repeating Alerts" and "Date-only Due Items" sections.

Replace the body:

```swift
public var body: some View {
    Form {
        Section("Repeating Alerts") {
            Toggle("Enable Nagging", isOn: $policy.isEnabled)

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

        Section("Escalation") {
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

        Section("Nag Mode") {
            Picker("Mode", selection: $policy.nagMode) {
                Text("Per Reminder").tag(NagMode.perReminder)
                Text("Per List").tag(NagMode.perList)
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
```

### Step 2: Add scenePhase replenishment to iOS app

In `NudgeIOSApp.swift`, add `@Environment(\.scenePhase)` and replenish on `.active`:

```swift
@main
struct NudgeIOSApp: App {
    @StateObject private var dependencies = IOSAppDependencies()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                NudgeRootView(
                    repository: dependencies.remindersRepository,
                    policyStore: dependencies.policyStore
                )
            }
            .environmentObject(dependencies.appController)
            .modelContainer(dependencies.modelContainer)
            .task {
                await dependencies.appController.requestPermissions()
                await dependencies.appController.replenishSchedule()
                dependencies.appController.activateBackgroundRefresh()
            }
            .onOpenURL { url in
                dependencies.appController.handle(url: url)
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task {
                        await dependencies.appController.replenishSchedule()
                    }
                }
            }
        }
    }
}
```

Also expose `policyStore` from `IOSAppDependencies`:

```swift
@MainActor
private final class IOSAppDependencies: ObservableObject {
    let modelContainer: ModelContainer
    let remindersRepository: EventKitRemindersRepository
    let policyStore: SwiftDataNagPolicyStore
    let appController: NagAppController

    init() {
        do {
            modelContainer = try ModelContainer(for: NagPolicyRecord.self, NagSessionRecord.self)
        } catch {
            fatalError("Unable to create SwiftData model container: \(error)")
        }

        remindersRepository = EventKitRemindersRepository()

        let policyStore = SwiftDataNagPolicyStore(context: modelContainer.mainContext)
        self.policyStore = policyStore
        let sessionStore = SwiftDataNagSessionStore(context: modelContainer.mainContext)
        let notificationClient = UserNotificationClient()

        let engine = NagEngine(
            remindersRepository: remindersRepository,
            policyStore: policyStore,
            sessionStore: sessionStore,
            notificationClient: notificationClient
        )

        appController = NagAppController(engine: engine)
    }
}
```

### Step 3: Build to verify compilation

Run: `swift build --package-path NagCorePackage`
Expected: Build succeeds

### Step 4: Run all tests

Run: `swift test --package-path NagCorePackage`
Expected: All pass

### Step 5: Commit

```bash
git add NagCorePackage/Sources/NagCore/UI/PolicySettingsView.swift Apps/iOS/NudgeIOSApp.swift
git commit -m "feat: strip quiet hours, add escalation UI, harden scenePhase refresh"
```

---

## Task 6: Add Engine Integration Tests

Add tests covering the newly wired flows: snooze through engine, stop nagging, per-list policy persistence.

**Files:**
- Modify: `NagCorePackage/Tests/NagCoreTests/NagEngineTests.swift`

### Step 1: Write test — snooze action pauses session

```swift
func testHandleSnoozePausesSession() async throws {
    let now = Date(timeIntervalSince1970: 1_700_100_000)
    let remindersRepository = MockRemindersRepository(reminders: [])
    let sessionStore = InMemoryNagSessionStore()
    let notificationClient = MockNotificationClient()
    let policyStore = StubNagPolicyStore()

    try sessionStore.save(
        NagSession(
            reminderID: "r1",
            reminderTitle: "Water plants",
            listTitle: "Home",
            dueDate: now.addingTimeInterval(-300),
            policyEnabled: true,
            intervalMinutes: 10,
            nagCount: 2,
            snoozeUntil: nil,
            lastNagAt: nil,
            stoppedAt: nil,
            nextEligibleAt: nil
        )
    )

    let engine = NagEngine(
        remindersRepository: remindersRepository,
        policyStore: policyStore,
        sessionStore: sessionStore,
        notificationClient: notificationClient
    )

    try await engine.handleNotificationAction(
        NotificationActionIDs.snooze(minutes: 15),
        reminderID: "r1",
        now: now
    )

    let session = sessionStore.session(for: "r1")!
    XCTAssertNotNil(session.snoozeUntil)
    XCTAssertEqual(session.snoozeUntil!.timeIntervalSince(now), 900, accuracy: 1)
    XCTAssertEqual(session.nextEligibleAt, session.snoozeUntil)
}
```

### Step 2: Write test — stop nagging stops session without completing reminder

```swift
func testHandleStopNaggingStopsSessionOnly() async throws {
    let now = Date(timeIntervalSince1970: 1_700_100_000)
    let remindersRepository = MockRemindersRepository(reminders: [])
    let sessionStore = InMemoryNagSessionStore()
    let notificationClient = MockNotificationClient()
    let policyStore = StubNagPolicyStore()

    try sessionStore.save(
        NagSession(
            reminderID: "r1",
            reminderTitle: "Water plants",
            listTitle: "Home",
            dueDate: now.addingTimeInterval(-300),
            policyEnabled: true,
            intervalMinutes: 10,
            nagCount: 3,
            snoozeUntil: nil,
            lastNagAt: nil,
            stoppedAt: nil,
            nextEligibleAt: nil
        )
    )

    let engine = NagEngine(
        remindersRepository: remindersRepository,
        policyStore: policyStore,
        sessionStore: sessionStore,
        notificationClient: notificationClient
    )

    try await engine.handleNotificationAction(
        NotificationActionIDs.stopNagging,
        reminderID: "r1",
        now: now
    )

    XCTAssertTrue(sessionStore.stoppedReminderIDs.contains("r1"))
    XCTAssertTrue(remindersRepository.completedReminderIDs.isEmpty, "Stop nagging should NOT complete the reminder")
}
```

### Step 3: Write test — per-list mode nags only enabled lists through engine

```swift
func testReplenishScheduleRespectsPerListMode() async throws {
    let now = Date(timeIntervalSince1970: 1_700_100_000)
    let workReminder = ReminderItem(
        id: "r1", title: "Work Task", notes: nil,
        dueDate: now.addingTimeInterval(-300), isCompleted: false,
        isFlagged: false, priority: 0,
        listID: "work", listTitle: "Work", hasTimeComponent: true
    )
    let homeReminder = ReminderItem(
        id: "r2", title: "Home Task", notes: nil,
        dueDate: now.addingTimeInterval(-300), isCompleted: false,
        isFlagged: false, priority: 0,
        listID: "home", listTitle: "Home", hasTimeComponent: true
    )

    let remindersRepository = MockRemindersRepository(reminders: [workReminder, homeReminder])
    let sessionStore = InMemoryNagSessionStore()
    let notificationClient = MockNotificationClient()
    let policyStore = StubNagPolicyStore(
        globalPolicy: NagPolicy(nagMode: .perList, nagEnabledListIDs: ["work"])
    )

    let engine = NagEngine(
        remindersRepository: remindersRepository,
        policyStore: policyStore,
        sessionStore: sessionStore,
        notificationClient: notificationClient
    )

    let decision = try await engine.replenishSchedule(now: now, perSessionCap: 2, globalCap: 10)

    XCTAssertEqual(decision.startedSessions.count, 1)
    XCTAssertEqual(decision.startedSessions.first?.reminderID, "r1")
    XCTAssertTrue(decision.scheduled.allSatisfy { $0.reminderID == "r1" })
}
```

### Step 4: Run all new tests

Run: `swift test --package-path NagCorePackage --filter "testHandleSnooze|testHandleStopNagging|testReplenishScheduleRespectsPerListMode"`
Expected: All PASS

### Step 5: Run full test suite

Run: `swift test --package-path NagCorePackage`
Expected: All pass

### Step 6: Commit

```bash
git add NagCorePackage/Tests/NagCoreTests/NagEngineTests.swift
git commit -m "test: add engine integration tests for snooze, stop, per-list mode"
```

---

## Task 7: Add Per-Reminder and Per-List Toggle UI

Add the UI for enabling nagging on individual reminders (perReminder mode) and lists (perList mode).

**Files:**
- Modify: `NagCorePackage/Sources/NagCore/UI/ReminderRowView.swift`
- Modify: `NagCorePackage/Sources/NagCore/UI/ReminderListView.swift`
- Modify: `NagCorePackage/Sources/NagCore/UI/ReminderDashboardView.swift`
- Modify: `NagCorePackage/Sources/NagCore/UI/PolicySettingsView.swift`
- Modify: `NagCorePackage/Sources/NagCore/UI/ReminderListViewModel.swift`

### Step 1: Add nag toggle to ReminderRowView

In `ReminderRowView.swift`, add an optional nag toggle:

```swift
public struct ReminderRowView: View {
    private let reminder: ReminderItem
    private let isNagging: Bool?
    private let onToggleComplete: () -> Void
    private let onQuickSnooze: () -> Void
    private let onToggleNag: (() -> Void)?

    public init(
        reminder: ReminderItem,
        isNagging: Bool? = nil,
        onToggleComplete: @escaping () -> Void,
        onQuickSnooze: @escaping () -> Void,
        onToggleNag: (() -> Void)? = nil
    ) {
        self.reminder = reminder
        self.isNagging = isNagging
        self.onToggleComplete = onToggleComplete
        self.onQuickSnooze = onQuickSnooze
        self.onToggleNag = onToggleNag
    }

    public var body: some View {
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

                HStack(spacing: 8) {
                    Text(reminder.listTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let dueDate = reminder.dueDate {
                        Text(dueDate, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)

            if let isNagging, let onToggleNag {
                Button(action: onToggleNag) {
                    Image(systemName: isNagging ? "bell.fill" : "bell.slash")
                        .foregroundStyle(isNagging ? .orange : .secondary)
                }
                .buttonStyle(.plain)
            }

            Button("Snooze", action: onQuickSnooze)
                .buttonStyle(.bordered)
                .font(.caption)
        }
        .padding(.vertical, 4)
    }
}
```

### Step 2: Thread nag toggle through ReminderListView

In `ReminderListView.swift`, add the callback and nag state:

```swift
public struct ReminderListView: View {
    private let reminders: [ReminderItem]
    private let nagStates: [String: Bool]
    private let onToggleCompletion: (ReminderItem) -> Void
    private let onQuickSnooze: (ReminderItem) -> Void
    private let onDelete: (ReminderItem) -> Void
    private let onToggleNag: ((ReminderItem) -> Void)?

    public init(
        reminders: [ReminderItem],
        nagStates: [String: Bool] = [:],
        onToggleCompletion: @escaping (ReminderItem) -> Void,
        onQuickSnooze: @escaping (ReminderItem) -> Void,
        onDelete: @escaping (ReminderItem) -> Void,
        onToggleNag: ((ReminderItem) -> Void)? = nil
    ) {
        self.reminders = reminders
        self.nagStates = nagStates
        self.onToggleCompletion = onToggleCompletion
        self.onQuickSnooze = onQuickSnooze
        self.onDelete = onDelete
        self.onToggleNag = onToggleNag
    }

    public var body: some View {
        List {
            ForEach(reminders) { reminder in
                ReminderRowView(
                    reminder: reminder,
                    isNagging: nagStates.isEmpty ? nil : nagStates[reminder.id] ?? false,
                    onToggleComplete: { onToggleCompletion(reminder) },
                    onQuickSnooze: { onQuickSnooze(reminder) },
                    onToggleNag: onToggleNag.map { handler in { handler(reminder) } }
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

### Step 3: Add nag state tracking to ReminderListViewModel

In `ReminderListViewModel.swift`, add a published property for per-reminder nag states:

```swift
@Published public private(set) var nagStates: [String: Bool] = [:]
```

Add methods to load nag states and toggle:

```swift
public func loadNagStates() {
    guard nagPolicy.nagMode == .perReminder, let store = policyStore else {
        nagStates = [:]
        return
    }
    let policies = store.allPoliciesByReminderID()
    nagStates = policies.mapValues(\.isEnabled)
}

public func toggleNag(for reminder: ReminderItem) {
    guard let store = policyStore else { return }
    let current = nagStates[reminder.id] ?? false
    var policy = store.policy(for: reminder.id) ?? nagPolicy
    policy.isEnabled = !current
    try? store.save(policy, for: reminder.id)
    nagStates[reminder.id] = !current
}
```

Call `loadNagStates()` at the end of `refresh()`:

```swift
public func refresh() async {
    isLoading = true
    defer { isLoading = false }

    do {
        reminders = try await remindersRepository.fetchReminders(in: selectedSmartList)
        errorMessage = nil
    } catch {
        errorMessage = error.localizedDescription
    }
    loadNagStates()
}
```

### Step 4: Add list picker to PolicySettingsView for perList mode

In `PolicySettingsView.swift`, add a `lists` binding and show list toggles when in perList mode.

Update the init and add a `lists` parameter:

```swift
public struct PolicySettingsView: View {
    @Binding private var policy: NagPolicy
    private let lists: [ReminderList]

    public init(policy: Binding<NagPolicy>, lists: [ReminderList] = []) {
        _policy = policy
        self.lists = lists
    }
```

Add a section to the form body (after the "Nag Mode" section):

```swift
if policy.nagMode == .perList && !lists.isEmpty {
    Section("Nag-Enabled Lists") {
        ForEach(lists) { list in
            Toggle(list.title, isOn: Binding(
                get: { policy.nagEnabledListIDs.contains(list.id) },
                set: { enabled in
                    if enabled {
                        policy.nagEnabledListIDs.insert(list.id)
                    } else {
                        policy.nagEnabledListIDs.remove(list.id)
                    }
                }
            ))
        }
    }
}
```

### Step 5: Fetch lists in ReminderListViewModel and wire to dashboard

In `ReminderListViewModel.swift`, add:

```swift
@Published public private(set) var lists: [ReminderList] = []
```

In `refresh()`, also fetch lists:

```swift
public func refresh() async {
    isLoading = true
    defer { isLoading = false }

    do {
        reminders = try await remindersRepository.fetchReminders(in: selectedSmartList)
        lists = try await remindersRepository.fetchLists()
        errorMessage = nil
    } catch {
        errorMessage = error.localizedDescription
    }
    loadNagStates()
}
```

### Step 6: Wire nag states and lists through dashboard

In `ReminderDashboardView.swift`, update the `ReminderListView` usage to pass nag states:

```swift
ReminderListView(
    reminders: viewModel.visibleReminders,
    nagStates: viewModel.nagPolicy.nagMode == .perReminder ? viewModel.nagStates : [:],
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
    onToggleNag: viewModel.nagPolicy.nagMode == .perReminder ? { reminder in
        viewModel.toggleNag(for: reminder)
    } : nil
)
```

Update the settings sheet to pass lists:

```swift
PolicySettingsView(policy: $viewModel.nagPolicy, lists: viewModel.lists)
```

### Step 7: Build to verify compilation

Run: `swift build --package-path NagCorePackage`
Expected: Build succeeds

### Step 8: Run all tests

Run: `swift test --package-path NagCorePackage`
Expected: All pass

### Step 9: Commit

```bash
git add NagCorePackage/Sources/NagCore/UI/ReminderRowView.swift NagCorePackage/Sources/NagCore/UI/ReminderListView.swift NagCorePackage/Sources/NagCore/UI/ReminderDashboardView.swift NagCorePackage/Sources/NagCore/UI/PolicySettingsView.swift NagCorePackage/Sources/NagCore/UI/ReminderListViewModel.swift
git commit -m "feat: add per-reminder nag toggle and per-list picker UI"
```

---

## Task 8: Final Verification

Run the full test suite and verify the package builds clean.

### Step 1: Run all tests

Run: `swift test --package-path NagCorePackage`
Expected: All pass

### Step 2: Build iOS target

Run: `swift build --package-path NagCorePackage`
Expected: Build succeeds with no warnings

### Step 3: Verify Xcode project generates

Run: `xcodegen generate`
Expected: Project generated successfully

### Step 4: Commit any remaining changes

```bash
git status
# If clean, nothing to do. Otherwise commit stragglers.
```
