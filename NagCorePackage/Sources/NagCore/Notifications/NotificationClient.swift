import Foundation

@MainActor
public protocol NotificationClient: AnyObject {
  func requestAuthorization() async throws -> Bool
  func registerNotificationCategories() async
  func pendingRequestIDs() async -> [String]
  func schedule(_ nags: [ScheduledNag]) async throws
  func removePendingRequests(withIDs identifiers: [String]) async
}

@MainActor
public final class MockNotificationClient: NotificationClient {
  public private(set) var scheduled: [ScheduledNag] = []
  public private(set) var removedIdentifiers: [String] = []
  public var grantsAuthorization = true

  public init() {}

  public func requestAuthorization() async throws -> Bool {
    grantsAuthorization
  }

  public func registerNotificationCategories() async {}

  public func pendingRequestIDs() async -> [String] {
    scheduled.map(\.identifier)
  }

  public func schedule(_ nags: [ScheduledNag]) async throws {
    var byIdentifier = Dictionary(uniqueKeysWithValues: scheduled.map { ($0.identifier, $0) })
    for nag in nags {
      byIdentifier[nag.identifier] = nag
    }
    scheduled = byIdentifier.values.sorted { $0.fireDate < $1.fireDate }
  }

  public func removePendingRequests(withIDs identifiers: [String]) async {
    removedIdentifiers.append(contentsOf: identifiers)
    let denied = Set(identifiers)
    scheduled.removeAll { denied.contains($0.identifier) }
  }
}
