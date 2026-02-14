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
      globalPolicy: .default,
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
      globalPolicy: .default,
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
      globalPolicy: .default,
      now: now
    )
    XCTAssertTrue(pausedDecision.scheduled.isEmpty)

    let resumedDecision = scheduler.buildSchedule(
      reminders: [reminder],
      existingSessions: [snoozedSession],
      policies: [:],
      globalPolicy: .default,
      now: now.addingTimeInterval(700)
    )
    XCTAssertFalse(resumedDecision.scheduled.isEmpty)
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
      globalPolicy: .default,
      now: now,
      perSessionCap: 5,
      globalCap: 40
    )

    XCTAssertLessThanOrEqual(decision.scheduled.count, 40)
    let grouped = Dictionary(grouping: decision.scheduled, by: \.reminderID)
    XCTAssertTrue(grouped.values.allSatisfy { $0.count <= 5 })
  }
}
