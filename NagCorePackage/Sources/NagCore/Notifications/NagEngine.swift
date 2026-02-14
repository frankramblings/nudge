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

    try sessionStore.save(decision.startedSessions)
    try sessionStore.save(decision.updatedSessions)
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
