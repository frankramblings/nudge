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
      listID: "nudge",
      listTitle: "Nudge",
      hasTimeComponent: true
    )
    let scheduler = NagScheduler()
    let decision = scheduler.buildSchedule(
      reminders: [reminder],
      existingSessions: [],
      policies: [:],
      globalPolicy: NagPolicy(),
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
      listID: "nudge",
      listTitle: "Nudge",
      hasTimeComponent: true
    )
    let existing = NagSession(
      reminderID: "r1",
      reminderTitle: "Check setting for heat",
      listTitle: "Nudge",
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
      globalPolicy: NagPolicy(),
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
      listID: "nudge",
      listTitle: "Nudge",
      hasTimeComponent: true
    )
    let snoozedSession = NagSession(
      reminderID: "r1",
      reminderTitle: "Feed Mr. Giggles",
      listTitle: "Nudge",
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
      globalPolicy: NagPolicy(),
      now: now
    )
    XCTAssertTrue(pausedDecision.scheduled.isEmpty)

    let resumedDecision = scheduler.buildSchedule(
      reminders: [reminder],
      existingSessions: [snoozedSession],
      policies: [:],
      globalPolicy: NagPolicy(),
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
      listID: "nudge",
      listTitle: "Nudge",
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
      listTitle: "Nudge",
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
      listTitle: "Nudge",
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

  func testOnlyNagsRemindersWithPolicyEnabled() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let enabled = ReminderItem(
      id: "r1", title: "Enabled", notes: nil,
      dueDate: now.addingTimeInterval(-300), isCompleted: false,
      isFlagged: false, priority: 0,
      listID: "nudge", listTitle: "Nudge", hasTimeComponent: true
    )
    let disabled = ReminderItem(
      id: "r2", title: "Disabled", notes: nil,
      dueDate: now.addingTimeInterval(-300), isCompleted: false,
      isFlagged: false, priority: 0,
      listID: "nudge", listTitle: "Nudge", hasTimeComponent: true
    )

    let globalPolicy = NagPolicy(isEnabled: true)
    let perReminder: [String: NagPolicy] = [
      "r2": NagPolicy(isEnabled: false)
    ]

    let scheduler = NagScheduler()
    let decision = scheduler.buildSchedule(
      reminders: [enabled, disabled],
      existingSessions: [],
      policies: perReminder,
      globalPolicy: globalPolicy,
      now: now,
      perSessionCap: 1
    )

    // r1 has no per-reminder policy so defaults to true (nagged)
    // r2 has isEnabled: false so should NOT be nagged
    XCTAssertEqual(decision.startedSessions.count, 1)
    XCTAssertEqual(decision.startedSessions.first?.reminderID, "r1")
    XCTAssertTrue(decision.scheduled.allSatisfy { $0.reminderID == "r1" })
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
        listID: "nudge",
        listTitle: "Nudge",
        hasTimeComponent: true
      )
    }

    let scheduler = NagScheduler()
    let decision = scheduler.buildSchedule(
      reminders: reminders,
      existingSessions: [],
      policies: [:],
      globalPolicy: NagPolicy(),
      now: now,
      perSessionCap: 5,
      globalCap: 40
    )

    XCTAssertLessThanOrEqual(decision.scheduled.count, 40)
    let grouped = Dictionary(grouping: decision.scheduled, by: \.reminderID)
    XCTAssertTrue(grouped.values.allSatisfy { $0.count <= 5 })
  }
}
