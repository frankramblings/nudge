import Foundation

@MainActor
public final class NagEngine {
  private let remindersRepository: any RemindersRepository
  private let policyStore: any NagPolicyStore
  private let sessionStore: any NagSessionStore
  private let notificationClient: any NotificationClient
  private let scheduler: NagScheduler

  public init(
    remindersRepository: any RemindersRepository,
    policyStore: any NagPolicyStore,
    sessionStore: any NagSessionStore,
    notificationClient: any NotificationClient,
    scheduler: NagScheduler = NagScheduler()
  ) {
    self.remindersRepository = remindersRepository
    self.policyStore = policyStore
    self.sessionStore = sessionStore
    self.notificationClient = notificationClient
    self.scheduler = scheduler
  }

  public func requestPermissions() async throws -> Bool {
    let remindersGranted = try await remindersRepository.requestAccess()
    let notificationsGranted = try await notificationClient.requestAuthorization()
    await notificationClient.registerNotificationCategories()
    return remindersGranted && notificationsGranted
  }

  @discardableResult
  public func replenishSchedule(
    now: Date = Date(),
    perSessionCap: Int = 5,
    globalCap: Int = 40
  ) async throws -> NagScheduleDecision {
    let nudgeListID = try await remindersRepository.ensureNudgeList()
    let reminders = try await remindersRepository.fetchReminders(inList: nudgeListID)
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

  public func handleNotificationAction(
    _ actionIdentifier: String,
    reminderID: String,
    now: Date = Date()
  ) async throws {
    switch actionIdentifier {
    case NotificationActionIDs.markDone:
      try await remindersRepository.setCompleted(reminderID: reminderID, isCompleted: true)
      try sessionStore.stopSession(reminderID: reminderID, at: now)
      await removePendingNotifications(for: reminderID)

    case NotificationActionIDs.stopNagging:
      try sessionStore.stopSession(reminderID: reminderID, at: now)
      await removePendingNotifications(for: reminderID)

    default:
      if let snoozeMinutes = NotificationActionIDs.snoozeMinutes(from: actionIdentifier),
         var session = sessionStore.session(for: reminderID) {
        let until = now.addingTimeInterval(Double(snoozeMinutes * 60))
        session.snoozeUntil = until
        session.nextEligibleAt = until
        try sessionStore.save(session)
        await removePendingNotifications(for: reminderID)
      }
    }
  }

  private func removePendingNotifications(for reminderID: String) async {
    let pendingIDs = await notificationClient.pendingRequestIDs()
    let matching = pendingIDs.filter { $0.hasPrefix("nag.\(reminderID).") }
    guard !matching.isEmpty else {
      return
    }

    await notificationClient.removePendingRequests(withIDs: matching)
  }
}
