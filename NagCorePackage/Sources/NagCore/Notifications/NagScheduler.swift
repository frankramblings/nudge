import Foundation

public struct NagScheduler {
  public init() {}

  public func buildSchedule(
    reminders: [ReminderItem],
    existingSessions: [NagSession],
    policies: [String: NagPolicy],
    globalPolicy: NagPolicy,
    now: Date,
    perSessionCap: Int = 5,
    globalCap: Int = 40
  ) -> NagScheduleDecision {
    let existingByID = Dictionary(uniqueKeysWithValues: existingSessions.map { ($0.reminderID, $0) })
    let reminderByID = Dictionary(uniqueKeysWithValues: reminders.map { ($0.id, $0) })

    var started: [NagSession] = []
    var updated: [NagSession] = []
    var stopped = Set<String>()
    var candidates: [ScheduledNag] = []

    for reminder in reminders {
      let perReminderPolicy = policies[reminder.id]
      let policy = perReminderPolicy ?? globalPolicy
      let effectiveDue = effectiveDueDate(for: reminder, policy: policy, now: now)
      let priorSession = existingByID[reminder.id]

      let isNagEnabled = perReminderPolicy?.isEnabled ?? true

      guard let due = effectiveDue, !reminder.isCompleted, isNagEnabled, due <= now else {
        if priorSession != nil {
          stopped.insert(reminder.id)
        }
        continue
      }

      var session = priorSession ?? NagSession(
        reminderID: reminder.id,
        reminderTitle: reminder.title,
        listTitle: reminder.listTitle,
        dueDate: due,
        policyEnabled: policy.isEnabled,
        intervalMinutes: policy.effectiveIntervalMinutes,
        nagCount: 0,
        snoozeUntil: nil,
        lastNagAt: nil,
        stoppedAt: nil,
        nextEligibleAt: nil
      )

      session.reminderTitle = reminder.title
      session.listTitle = reminder.listTitle
      session.dueDate = due
      session.policyEnabled = policy.isEnabled
      session.intervalMinutes = resolvedInterval(for: session, policy: policy)
      if let snoozeUntil = session.snoozeUntil, snoozeUntil <= now {
        session.snoozeUntil = nil
      }

      if priorSession == nil {
        started.append(session)
      } else {
        updated.append(session)
      }

      guard session.stoppedAt == nil else {
        continue
      }

      if let snoozeUntil = session.snoozeUntil, snoozeUntil > now {
        continue
      }

      let base = max(now.addingTimeInterval(5), session.nextEligibleAt ?? now.addingTimeInterval(5))
      let body = notificationBody(for: reminder, dueDate: due)

      for sequence in 0..<max(perSessionCap, 0) {
        let fireDate = base.addingTimeInterval(Double(sequence * max(session.intervalMinutes, 1)) * 60)
        candidates.append(
          ScheduledNag(
            identifier: "nag.\(reminder.id).\(Int(fireDate.timeIntervalSince1970))",
            reminderID: reminder.id,
            title: reminder.title,
            body: body,
            fireDate: fireDate,
            sequenceIndex: sequence
          )
        )
      }
    }

    for existing in existingSessions where reminderByID[existing.reminderID] == nil {
      stopped.insert(existing.reminderID)
    }

    let finalScheduled = candidates
      .sorted(by: { $0.fireDate < $1.fireDate })
      .prefix(max(globalCap, 0))

    return NagScheduleDecision(
      startedSessions: started,
      updatedSessions: updated,
      stoppedSessionIDs: Array(stopped).sorted(),
      scheduled: Array(finalScheduled)
    )
  }

  private func resolvedInterval(for session: NagSession, policy: NagPolicy) -> Int {
    guard let escalationAfter = policy.escalationAfterNags,
          let escalatedInterval = policy.escalationIntervalMinutes,
          session.nagCount >= escalationAfter else {
      return max(policy.effectiveIntervalMinutes, 1)
    }

    return max(escalatedInterval, 1)
  }

  private func effectiveDueDate(for reminder: ReminderItem, policy: NagPolicy, now: Date) -> Date? {
    guard let due = reminder.dueDate else {
      return nil
    }

    guard reminder.hasTimeComponent == false else {
      return due
    }

    var components = Calendar.current.dateComponents([.year, .month, .day], from: due)
    components.hour = min(max(policy.dateOnlyDueHour, 0), 23)
    components.minute = 0
    components.second = 0
    components.timeZone = Calendar.current.timeZone
    return Calendar.current.date(from: components) ?? now
  }

  private func notificationBody(for reminder: ReminderItem, dueDate: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    let dueText = formatter.string(from: dueDate)
    return "\(reminder.listTitle) • Due \(dueText)"
  }
}
