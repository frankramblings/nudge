import Foundation
import SwiftData

@Model
public final class NagPolicyRecord {
  @Attribute(.unique) public var key: String
  public var isEnabled: Bool
  public var intervalMinutes: Int
  public var customIntervalMinutes: Int?
  public var quietHoursEnabled: Bool
  public var quietHoursStartHour: Int
  public var quietHoursEndHour: Int
  public var escalationAfterNags: Int?
  public var escalationIntervalMinutes: Int?
  public var dateOnlyDueHour: Int
  public var repeatAtLeast: Int
  public var repeatIndefinitelyModeRaw: String
  public var snoozePresetMinutesRaw: String

  public init(
    key: String,
    isEnabled: Bool,
    intervalMinutes: Int,
    customIntervalMinutes: Int?,
    quietHoursEnabled: Bool,
    quietHoursStartHour: Int,
    quietHoursEndHour: Int,
    escalationAfterNags: Int?,
    escalationIntervalMinutes: Int?,
    dateOnlyDueHour: Int,
    repeatAtLeast: Int,
    repeatIndefinitelyModeRaw: String,
    snoozePresetMinutesRaw: String
  ) {
    self.key = key
    self.isEnabled = isEnabled
    self.intervalMinutes = intervalMinutes
    self.customIntervalMinutes = customIntervalMinutes
    self.quietHoursEnabled = quietHoursEnabled
    self.quietHoursStartHour = quietHoursStartHour
    self.quietHoursEndHour = quietHoursEndHour
    self.escalationAfterNags = escalationAfterNags
    self.escalationIntervalMinutes = escalationIntervalMinutes
    self.dateOnlyDueHour = dateOnlyDueHour
    self.repeatAtLeast = repeatAtLeast
    self.repeatIndefinitelyModeRaw = repeatIndefinitelyModeRaw
    self.snoozePresetMinutesRaw = snoozePresetMinutesRaw
  }
}

@MainActor
public protocol NagPolicyStore: AnyObject {
  func globalPolicy() -> NagPolicy
  func policy(for reminderID: String) -> NagPolicy?
  func allPoliciesByReminderID() -> [String: NagPolicy]
  func save(_ policy: NagPolicy, for reminderID: String?) throws
  func deletePolicy(for reminderID: String) throws
}

@MainActor
public final class SwiftDataNagPolicyStore: NagPolicyStore {
  public static let globalKey = "global"

  private let context: ModelContext

  public init(context: ModelContext) {
    self.context = context
  }

  public func globalPolicy() -> NagPolicy {
    if let record = fetchRecord(forKey: Self.globalKey) {
      return decode(record: record)
    }

    let fallback = NagPolicy.default
    try? save(fallback, for: nil)
    return fallback
  }

  public func policy(for reminderID: String) -> NagPolicy? {
    fetchRecord(forKey: reminderID).map(decode(record:))
  }

  public func allPoliciesByReminderID() -> [String: NagPolicy] {
    let descriptor = FetchDescriptor<NagPolicyRecord>()
    guard let records = try? context.fetch(descriptor) else {
      return [:]
    }

    var mapped: [String: NagPolicy] = [:]
    for record in records where record.key != Self.globalKey {
      mapped[record.key] = decode(record: record)
    }
    return mapped
  }

  public func save(_ policy: NagPolicy, for reminderID: String?) throws {
    let key = reminderID ?? Self.globalKey
    if let existing = fetchRecord(forKey: key) {
      apply(policy: policy, to: existing)
    } else {
      let record = NagPolicyRecord(
        key: key,
        isEnabled: policy.isEnabled,
        intervalMinutes: policy.intervalMinutes,
        customIntervalMinutes: policy.customIntervalMinutes,
        quietHoursEnabled: policy.quietHoursEnabled,
        quietHoursStartHour: policy.quietHoursStartHour,
        quietHoursEndHour: policy.quietHoursEndHour,
        escalationAfterNags: policy.escalationAfterNags,
        escalationIntervalMinutes: policy.escalationIntervalMinutes,
        dateOnlyDueHour: policy.dateOnlyDueHour,
        repeatAtLeast: policy.repeatAtLeast,
        repeatIndefinitelyModeRaw: policy.repeatIndefinitelyMode.rawValue,
        snoozePresetMinutesRaw: encode(minutes: policy.snoozePresetMinutes)
      )
      context.insert(record)
    }
    try context.save()
  }

  public func deletePolicy(for reminderID: String) throws {
    guard let record = fetchRecord(forKey: reminderID) else {
      return
    }
    context.delete(record)
    try context.save()
  }

  private func fetchRecord(forKey key: String) -> NagPolicyRecord? {
    let descriptor = FetchDescriptor<NagPolicyRecord>(
      predicate: #Predicate { $0.key == key }
    )
    return try? context.fetch(descriptor).first
  }

  private func apply(policy: NagPolicy, to record: NagPolicyRecord) {
    record.isEnabled = policy.isEnabled
    record.intervalMinutes = policy.intervalMinutes
    record.customIntervalMinutes = policy.customIntervalMinutes
    record.quietHoursEnabled = policy.quietHoursEnabled
    record.quietHoursStartHour = policy.quietHoursStartHour
    record.quietHoursEndHour = policy.quietHoursEndHour
    record.escalationAfterNags = policy.escalationAfterNags
    record.escalationIntervalMinutes = policy.escalationIntervalMinutes
    record.dateOnlyDueHour = policy.dateOnlyDueHour
    record.repeatAtLeast = policy.repeatAtLeast
    record.repeatIndefinitelyModeRaw = policy.repeatIndefinitelyMode.rawValue
    record.snoozePresetMinutesRaw = encode(minutes: policy.snoozePresetMinutes)
  }

  private func decode(record: NagPolicyRecord) -> NagPolicy {
    NagPolicy(
      isEnabled: record.isEnabled,
      intervalMinutes: record.intervalMinutes,
      customIntervalMinutes: record.customIntervalMinutes,
      quietHoursEnabled: record.quietHoursEnabled,
      quietHoursStartHour: record.quietHoursStartHour,
      quietHoursEndHour: record.quietHoursEndHour,
      escalationAfterNags: record.escalationAfterNags,
      escalationIntervalMinutes: record.escalationIntervalMinutes,
      dateOnlyDueHour: record.dateOnlyDueHour,
      repeatAtLeast: record.repeatAtLeast,
      repeatIndefinitelyMode: RepeatIndefinitelyMode(rawValue: record.repeatIndefinitelyModeRaw) ?? .whenPossible,
      snoozePresetMinutes: decodeMinutes(raw: record.snoozePresetMinutesRaw)
    )
  }

  private func encode(minutes: [Int]) -> String {
    minutes.map(String.init).joined(separator: ",")
  }

  private func decodeMinutes(raw: String) -> [Int] {
    raw
      .split(separator: ",")
      .compactMap { Int($0) }
      .filter { $0 > 0 }
  }
}
