import Foundation

public enum RepeatIndefinitelyMode: String, CaseIterable, Codable, Sendable {
  case off
  case whenPossible
  case always
}

public enum NagMode: String, CaseIterable, Codable, Sendable {
  case perReminder
  case perList
}

public struct NagPolicy: Equatable, Codable, Sendable {
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
  public var repeatIndefinitelyMode: RepeatIndefinitelyMode
  public var snoozePresetMinutes: [Int]
  public var nagMode: NagMode
  public var nagEnabledListIDs: Set<String>

  public init(
    isEnabled: Bool = true,
    intervalMinutes: Int = 10,
    customIntervalMinutes: Int? = nil,
    quietHoursEnabled: Bool = false,
    quietHoursStartHour: Int = 22,
    quietHoursEndHour: Int = 7,
    escalationAfterNags: Int? = nil,
    escalationIntervalMinutes: Int? = nil,
    dateOnlyDueHour: Int = 9,
    repeatAtLeast: Int = 10,
    repeatIndefinitelyMode: RepeatIndefinitelyMode = .whenPossible,
    snoozePresetMinutes: [Int] = [5, 10, 20, 60],
    nagMode: NagMode = .perList,
    nagEnabledListIDs: Set<String> = []
  ) {
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
    self.repeatIndefinitelyMode = repeatIndefinitelyMode
    self.snoozePresetMinutes = snoozePresetMinutes
    self.nagMode = nagMode
    self.nagEnabledListIDs = nagEnabledListIDs
  }

  public var effectiveIntervalMinutes: Int {
    customIntervalMinutes ?? intervalMinutes
  }

  public static let `default` = NagPolicy()
}
