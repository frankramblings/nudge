import Foundation

public struct NagSession: Identifiable, Hashable, Sendable {
  public var id: String { reminderID }
  public var reminderID: String
  public var reminderTitle: String
  public var listTitle: String
  public var dueDate: Date
  public var policyEnabled: Bool
  public var intervalMinutes: Int
  public var nagCount: Int
  public var snoozeUntil: Date?
  public var lastNagAt: Date?
  public var stoppedAt: Date?
  public var nextEligibleAt: Date?

  public init(
    reminderID: String,
    reminderTitle: String,
    listTitle: String,
    dueDate: Date,
    policyEnabled: Bool,
    intervalMinutes: Int,
    nagCount: Int,
    snoozeUntil: Date?,
    lastNagAt: Date?,
    stoppedAt: Date?,
    nextEligibleAt: Date?
  ) {
    self.reminderID = reminderID
    self.reminderTitle = reminderTitle
    self.listTitle = listTitle
    self.dueDate = dueDate
    self.policyEnabled = policyEnabled
    self.intervalMinutes = intervalMinutes
    self.nagCount = nagCount
    self.snoozeUntil = snoozeUntil
    self.lastNagAt = lastNagAt
    self.stoppedAt = stoppedAt
    self.nextEligibleAt = nextEligibleAt
  }
}

public struct ScheduledNag: Hashable, Sendable {
  public var identifier: String
  public var reminderID: String
  public var title: String
  public var body: String
  public var fireDate: Date
  public var sequenceIndex: Int

  public init(
    identifier: String,
    reminderID: String,
    title: String,
    body: String,
    fireDate: Date,
    sequenceIndex: Int
  ) {
    self.identifier = identifier
    self.reminderID = reminderID
    self.title = title
    self.body = body
    self.fireDate = fireDate
    self.sequenceIndex = sequenceIndex
  }
}

public struct NagScheduleDecision: Sendable {
  public var startedSessions: [NagSession]
  public var updatedSessions: [NagSession]
  public var stoppedSessionIDs: [String]
  public var scheduled: [ScheduledNag]

  public init(
    startedSessions: [NagSession],
    updatedSessions: [NagSession],
    stoppedSessionIDs: [String],
    scheduled: [ScheduledNag]
  ) {
    self.startedSessions = startedSessions
    self.updatedSessions = updatedSessions
    self.stoppedSessionIDs = stoppedSessionIDs
    self.scheduled = scheduled
  }
}
