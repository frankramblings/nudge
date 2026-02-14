import Foundation

public enum DeepLinkRoute: Equatable, Sendable {
  case reminder(reminderID: String)
  case snooze(reminderID: String, minutes: Int)
  case nagScreen(reminderID: String)
}

public struct DeepLinkRouter {
  public init() {}

  public func route(for url: URL) -> DeepLinkRoute? {
    let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    let pathComponents = url.pathComponents.filter { $0 != "/" }

    let command = url.host?.lowercased() ?? pathComponents.first?.lowercased()
    let reminderID = queryItems.first(where: { $0.name == "reminderID" })?.value
      ?? queryItems.first(where: { $0.name == "id" })?.value
      ?? pathComponents.dropFirst().first

    switch command {
    case "reminder":
      guard let reminderID else {
        return nil
      }
      return .reminder(reminderID: reminderID)

    case "snooze":
      guard let reminderID else {
        return nil
      }
      let minutes = max(Int(queryItems.first(where: { $0.name == "minutes" })?.value ?? "10") ?? 10, 1)
      return .snooze(reminderID: reminderID, minutes: minutes)

    case "nag-screen", "nag":
      guard let reminderID else {
        return nil
      }
      return .nagScreen(reminderID: reminderID)

    default:
      return nil
    }
  }
}
