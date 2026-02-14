import Foundation
import SwiftData

@Model
public final class NagSessionRecord {
  @Attribute(.unique) public var reminderID: String
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

@MainActor
public protocol NagSessionStore: AnyObject {
  func allSessions() -> [NagSession]
  func session(for reminderID: String) -> NagSession?
  func save(_ session: NagSession) throws
  func save(_ sessions: [NagSession]) throws
  func stopSession(reminderID: String, at: Date) throws
  func deleteSession(reminderID: String) throws
}

@MainActor
public final class SwiftDataNagSessionStore: NagSessionStore {
  private let context: ModelContext

  public init(context: ModelContext) {
    self.context = context
  }

  public func allSessions() -> [NagSession] {
    let descriptor = FetchDescriptor<NagSessionRecord>()
    guard let records = try? context.fetch(descriptor) else {
      return []
    }

    return records.map(decode(record:))
  }

  public func session(for reminderID: String) -> NagSession? {
    fetchRecord(reminderID: reminderID).map(decode(record:))
  }

  public func save(_ session: NagSession) throws {
    if let record = fetchRecord(reminderID: session.reminderID) {
      apply(session: session, to: record)
    } else {
      context.insert(record(for: session))
    }

    try context.save()
  }

  public func save(_ sessions: [NagSession]) throws {
    for session in sessions {
      if let record = fetchRecord(reminderID: session.reminderID) {
        apply(session: session, to: record)
      } else {
        context.insert(record(for: session))
      }
    }

    try context.save()
  }

  public func stopSession(reminderID: String, at: Date) throws {
    guard let record = fetchRecord(reminderID: reminderID) else {
      return
    }

    record.stoppedAt = at
    record.nextEligibleAt = nil
    try context.save()
  }

  public func deleteSession(reminderID: String) throws {
    guard let record = fetchRecord(reminderID: reminderID) else {
      return
    }

    context.delete(record)
    try context.save()
  }

  private func fetchRecord(reminderID: String) -> NagSessionRecord? {
    let descriptor = FetchDescriptor<NagSessionRecord>(
      predicate: #Predicate { $0.reminderID == reminderID }
    )
    return try? context.fetch(descriptor).first
  }

  private func record(for session: NagSession) -> NagSessionRecord {
    NagSessionRecord(
      reminderID: session.reminderID,
      reminderTitle: session.reminderTitle,
      listTitle: session.listTitle,
      dueDate: session.dueDate,
      policyEnabled: session.policyEnabled,
      intervalMinutes: session.intervalMinutes,
      nagCount: session.nagCount,
      snoozeUntil: session.snoozeUntil,
      lastNagAt: session.lastNagAt,
      stoppedAt: session.stoppedAt,
      nextEligibleAt: session.nextEligibleAt
    )
  }

  private func apply(session: NagSession, to record: NagSessionRecord) {
    record.reminderTitle = session.reminderTitle
    record.listTitle = session.listTitle
    record.dueDate = session.dueDate
    record.policyEnabled = session.policyEnabled
    record.intervalMinutes = session.intervalMinutes
    record.nagCount = session.nagCount
    record.snoozeUntil = session.snoozeUntil
    record.lastNagAt = session.lastNagAt
    record.stoppedAt = session.stoppedAt
    record.nextEligibleAt = session.nextEligibleAt
  }

  private func decode(record: NagSessionRecord) -> NagSession {
    NagSession(
      reminderID: record.reminderID,
      reminderTitle: record.reminderTitle,
      listTitle: record.listTitle,
      dueDate: record.dueDate,
      policyEnabled: record.policyEnabled,
      intervalMinutes: record.intervalMinutes,
      nagCount: record.nagCount,
      snoozeUntil: record.snoozeUntil,
      lastNagAt: record.lastNagAt,
      stoppedAt: record.stoppedAt,
      nextEligibleAt: record.nextEligibleAt
    )
  }
}

@MainActor
public final class InMemoryNagSessionStore: NagSessionStore {
  public private(set) var stoppedReminderIDs = Set<String>()

  private var byReminderID: [String: NagSession] = [:]

  public init() {}

  public func allSessions() -> [NagSession] {
    byReminderID.values.sorted { $0.dueDate < $1.dueDate }
  }

  public func session(for reminderID: String) -> NagSession? {
    byReminderID[reminderID]
  }

  public func save(_ session: NagSession) throws {
    byReminderID[session.reminderID] = session
  }

  public func save(_ sessions: [NagSession]) throws {
    for session in sessions {
      byReminderID[session.reminderID] = session
    }
  }

  public func stopSession(reminderID: String, at: Date) throws {
    guard var existing = byReminderID[reminderID] else {
      return
    }

    existing.stoppedAt = at
    existing.nextEligibleAt = nil
    byReminderID[reminderID] = existing
    stoppedReminderIDs.insert(reminderID)
  }

  public func deleteSession(reminderID: String) throws {
    byReminderID[reminderID] = nil
  }
}
