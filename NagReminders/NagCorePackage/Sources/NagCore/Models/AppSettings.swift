import Foundation

public enum AppTheme: String, CaseIterable, Codable, Sendable {
  case system
  case light
  case dark
}

public enum SoundProfile: String, CaseIterable, Codable, Sendable {
  case system
  case loudTone
  case softTone
}

public struct AppSettings: Codable, Sendable {
  public var alertsEnabled: Bool
  public var badgesEnabled: Bool
  public var hapticsEnabled: Bool
  public var soundEffectsEnabled: Bool
  public var theme: AppTheme
  public var soundProfile: SoundProfile
  public var swipeCompletes: Bool
  public var repeatAtLeast: Int
  public var repeatIndefinitelyMode: RepeatIndefinitelyMode
  public var snoozePresets: [Int]
  public var dateOnlyDueHour: Int
  public var quickSnoozeTimes: [Int]

  public init(
    alertsEnabled: Bool = true,
    badgesEnabled: Bool = true,
    hapticsEnabled: Bool = true,
    soundEffectsEnabled: Bool = true,
    theme: AppTheme = .system,
    soundProfile: SoundProfile = .system,
    swipeCompletes: Bool = true,
    repeatAtLeast: Int = 10,
    repeatIndefinitelyMode: RepeatIndefinitelyMode = .whenPossible,
    snoozePresets: [Int] = [5, 10, 20, 60],
    dateOnlyDueHour: Int = 9,
    quickSnoozeTimes: [Int] = [9, 12, 17, 21]
  ) {
    self.alertsEnabled = alertsEnabled
    self.badgesEnabled = badgesEnabled
    self.hapticsEnabled = hapticsEnabled
    self.soundEffectsEnabled = soundEffectsEnabled
    self.theme = theme
    self.soundProfile = soundProfile
    self.swipeCompletes = swipeCompletes
    self.repeatAtLeast = repeatAtLeast
    self.repeatIndefinitelyMode = repeatIndefinitelyMode
    self.snoozePresets = snoozePresets
    self.dateOnlyDueHour = dateOnlyDueHour
    self.quickSnoozeTimes = quickSnoozeTimes
  }
}
