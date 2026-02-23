import XCTest
@testable import NagCore

final class NagSchedulerTests: XCTestCase {
  func testStartSessionWhenOverdue() {
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
    let scheduler = NagScheduler()
    let decision = scheduler.buildSchedule(
      reminders: [reminder],
      existingSessions: [],
      policies: [:],
      globalPolicy: NagPolicy(nagEnabledListIDs: ["list-1"]),
      now: now,
      perSessionCap: 1
    )

    XCTAssertEqual(decision.startedSessions.count, 1)
    XCTAssertEqual(decision.scheduled.count, 1)
  }

  func testStopSessionWhenCompleted() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let reminder = ReminderItem(
      id: "r1",
      title: "Check setting for heat",
      notes: nil,
      dueDate: now.addingTimeInterval(-600),
      isCompleted: true,
      isFlagged: false,
      priority: 0,
      listID: "list-1",
      listTitle: "Reminders",
      hasTimeComponent: true
    )
    let existing = NagSession(
      reminderID: "r1",
      reminderTitle: "Check setting for heat",
      listTitle: "Reminders",
      dueDate: now.addingTimeInterval(-600),
      policyEnabled: true,
      intervalMinutes: 10,
      nagCount: 2,
      snoozeUntil: nil,
      lastNagAt: nil,
      stoppedAt: nil,
      nextEligibleAt: nil
    )

    let scheduler = NagScheduler()
    let decision = scheduler.buildSchedule(
      reminders: [reminder],
      existingSessions: [existing],
      policies: [:],
      globalPolicy: NagPolicy(nagEnabledListIDs: ["list-1"]),
      now: now
    )

    XCTAssertTrue(decision.stoppedSessionIDs.contains("r1"))
    XCTAssertTrue(decision.scheduled.isEmpty)
  }

  func testPauseAndResumeOnSnoozeUntil() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let reminder = ReminderItem(
      id: "r1",
      title: "Feed Mr. Giggles",
      notes: nil,
      dueDate: now.addingTimeInterval(-600),
      isCompleted: false,
      isFlagged: false,
      priority: 0,
      listID: "list-1",
      listTitle: "Reminders",
      hasTimeComponent: true
    )
    let snoozedSession = NagSession(
      reminderID: "r1",
      reminderTitle: "Feed Mr. Giggles",
      listTitle: "Reminders",
      dueDate: now.addingTimeInterval(-600),
      policyEnabled: true,
      intervalMinutes: 5,
      nagCount: 4,
      snoozeUntil: now.addingTimeInterval(600),
      lastNagAt: nil,
      stoppedAt: nil,
      nextEligibleAt: nil
    )

    let scheduler = NagScheduler()
    let pausedDecision = scheduler.buildSchedule(
      reminders: [reminder],
      existingSessions: [snoozedSession],
      policies: [:],
      globalPolicy: NagPolicy(nagEnabledListIDs: ["list-1"]),
      now: now
    )
    XCTAssertTrue(pausedDecision.scheduled.isEmpty)

    let resumedDecision = scheduler.buildSchedule(
      reminders: [reminder],
      existingSessions: [snoozedSession],
      policies: [:],
      globalPolicy: NagPolicy(nagEnabledListIDs: ["list-1"]),
      now: now.addingTimeInterval(700)
    )
    XCTAssertFalse(resumedDecision.scheduled.isEmpty)
  }

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
      escalationIntervalMinutes: 2,
      nagEnabledListIDs: ["list-1"]
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

  func testRollingSchedulingRespectsSessionAndGlobalCaps() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let reminders: [ReminderItem] = (0..<20).map { index in
      ReminderItem(
        id: "r\(index)",
        title: "Reminder \(index)",
        notes: nil,
        dueDate: now.addingTimeInterval(-Double(index + 1) * 60),
        isCompleted: false,
        isFlagged: false,
        priority: 0,
        listID: "list-1",
        listTitle: "Reminders",
        hasTimeComponent: true
      )
    }

    let scheduler = NagScheduler()
    let decision = scheduler.buildSchedule(
      reminders: reminders,
      existingSessions: [],
      policies: [:],
      globalPolicy: NagPolicy(nagEnabledListIDs: ["list-1"]),
      now: now,
      perSessionCap: 5,
      globalCap: 40
    )

    XCTAssertLessThanOrEqual(decision.scheduled.count, 40)
    let grouped = Dictionary(grouping: decision.scheduled, by: \.reminderID)
    XCTAssertTrue(grouped.values.allSatisfy { $0.count <= 5 })
  }
}
