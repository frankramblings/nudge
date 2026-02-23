import XCTest
@testable import NagCore

@MainActor
final class NagEngineTests: XCTestCase {
  func testReplenishScheduleStartsSessionAndSchedulesNotifications() async throws {
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

    let decision = try await engine.replenishSchedule(now: now, perSessionCap: 2, globalCap: 2)

    XCTAssertEqual(decision.startedSessions.count, 1)
    XCTAssertEqual(sessionStore.allSessions().count, 1)
    XCTAssertEqual(notificationClient.scheduled.count, 2)
  }

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

  func testHandleMarkDoneStopsSessionAndCompletesReminder() async throws {
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
        nagCount: 1,
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

    try await engine.handleNotificationAction(NotificationActionIDs.markDone, reminderID: "r1", now: now)

    XCTAssertEqual(remindersRepository.completedReminderIDs, ["r1"])
    XCTAssertTrue(sessionStore.stoppedReminderIDs.contains("r1"))
  }
}

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
