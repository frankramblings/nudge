import Foundation
import UserNotifications

public final class NagNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
  private let onAction: @Sendable (String, String) async -> Void
  private let onOpenDeepLink: @Sendable (URL) -> Void

  public init(
    onAction: @escaping @Sendable (String, String) async -> Void,
    onOpenDeepLink: @escaping @Sendable (URL) -> Void
  ) {
    self.onAction = onAction
    self.onOpenDeepLink = onOpenDeepLink
  }

  // Show notifications even when the app is in the foreground
  public func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound, .badge])
  }

  // Handle notification action taps (snooze, mark done, stop nagging)
  public func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo
    let actionIdentifier = response.actionIdentifier

    if actionIdentifier == UNNotificationDefaultActionIdentifier {
      // User tapped the notification itself — open deep link
      if let deepLinkString = userInfo[NotificationUserInfoKeys.deepLink] as? String,
         let url = URL(string: deepLinkString) {
        onOpenDeepLink(url)
      }
      completionHandler()
      return
    }

    guard let reminderID = userInfo[NotificationUserInfoKeys.reminderID] as? String else {
      completionHandler()
      return
    }

    Task {
      await onAction(actionIdentifier, reminderID)
      completionHandler()
    }
  }
}
