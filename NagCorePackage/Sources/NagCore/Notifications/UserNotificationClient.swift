import Foundation
import UserNotifications

@MainActor
public final class UserNotificationClient: NotificationClient {
  private let center: UNUserNotificationCenter

  public init(center: UNUserNotificationCenter = .current()) {
    self.center = center
  }

  public func requestAuthorization() async throws -> Bool {
    #if os(macOS)
    let options: UNAuthorizationOptions = [.alert, .badge, .sound]
    #else
    let options: UNAuthorizationOptions = [.alert, .badge, .sound, .timeSensitive]
    #endif

    return try await center.requestAuthorization(options: options)
  }

  public func registerNotificationCategories() async {
    let snoozeFive = UNNotificationAction(
      identifier: NotificationActionIDs.snooze(minutes: 5),
      title: "Snooze 5m",
      options: []
    )
    let snoozeTwenty = UNNotificationAction(
      identifier: NotificationActionIDs.snooze(minutes: 20),
      title: "Snooze 20m",
      options: []
    )
    let markDone = UNNotificationAction(
      identifier: NotificationActionIDs.markDone,
      title: "Mark Done",
      options: [.authenticationRequired]
    )
    let stopNagging = UNNotificationAction(
      identifier: NotificationActionIDs.stopNagging,
      title: "Stop Nagging",
      options: [.destructive]
    )

    let category = UNNotificationCategory(
      identifier: NotificationCategoryIDs.nag,
      actions: [markDone, snoozeFive, snoozeTwenty, stopNagging],
      intentIdentifiers: [],
      options: []
    )

    center.setNotificationCategories([category])
  }

  public func pendingRequestIDs() async -> [String] {
    await withCheckedContinuation { continuation in
      center.getPendingNotificationRequests { requests in
        continuation.resume(returning: requests.map(\.identifier))
      }
    }
  }

  public func schedule(_ nags: [ScheduledNag]) async throws {
    for nag in nags {
      let content = UNMutableNotificationContent()
      content.title = nag.title
      content.body = nag.body
      content.sound = .default
      #if !os(macOS)
      content.interruptionLevel = .timeSensitive
      #endif
      content.categoryIdentifier = NotificationCategoryIDs.nag
      content.userInfo = [
        NotificationUserInfoKeys.reminderID: nag.reminderID,
        NotificationUserInfoKeys.deepLink: DeepLinkFactory.nagScreenURL(reminderID: nag.reminderID).absoluteString,
      ]

      let components = Calendar.current.dateComponents(
        [.year, .month, .day, .hour, .minute, .second],
        from: nag.fireDate
      )
      let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
      let request = UNNotificationRequest(identifier: nag.identifier, content: content, trigger: trigger)

      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        center.add(request) { error in
          if let error {
            continuation.resume(throwing: error)
          } else {
            continuation.resume(returning: ())
          }
        }
      }
    }
  }

  public func removePendingRequests(withIDs identifiers: [String]) async {
    center.removePendingNotificationRequests(withIdentifiers: identifiers)
  }
}
