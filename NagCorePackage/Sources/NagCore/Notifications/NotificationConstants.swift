import Foundation

public enum NotificationCategoryIDs {
  public static let nag = "NUDGE_NAG_CATEGORY"
}

public enum NotificationActionIDs {
  public static let markDone = "NUDGE_MARK_DONE"
  public static let stopNagging = "NUDGE_STOP_NAGGING"
  public static let openSnooze = "NUDGE_OPEN_SNOOZE"

  public static func snooze(minutes: Int) -> String {
    "NUDGE_SNOOZE_\(max(minutes, 1))"
  }

  public static func snoozeMinutes(from actionIdentifier: String) -> Int? {
    guard actionIdentifier.hasPrefix("NUDGE_SNOOZE_") else {
      return nil
    }

    return Int(actionIdentifier.replacingOccurrences(of: "NUDGE_SNOOZE_", with: ""))
  }
}

public enum NotificationUserInfoKeys {
  public static let reminderID = "reminderID"
  public static let deepLink = "deepLink"
}

public enum DeepLinkFactory {
  public static func reminderURL(reminderID: String) -> URL {
    URL(string: "nudge://reminder?id=\(reminderID)")!
  }

  public static func snoozeURL(reminderID: String, minutes: Int) -> URL {
    URL(string: "nudge://snooze?reminderID=\(reminderID)&minutes=\(max(minutes, 1))")!
  }

  public static func nagScreenURL(reminderID: String) -> URL {
    URL(string: "nudge://nag-screen?reminderID=\(reminderID)")!
  }
}
