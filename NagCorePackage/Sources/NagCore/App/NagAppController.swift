import Foundation
import SwiftUI

@MainActor
public final class NagAppController: ObservableObject {
  @Published public private(set) var selectedReminderID: String?
  @Published public private(set) var nagScreenReminderID: String?
  @Published public private(set) var quickSnoozeSelection: (reminderID: String, minutes: Int)?
  @Published public private(set) var lastErrorMessage: String?

  private let engine: NagEngine
  private let deepLinkRouter: DeepLinkRouter
  private let backgroundRefreshCoordinator: BackgroundRefreshCoordinator

  public init(
    engine: NagEngine,
    deepLinkRouter: DeepLinkRouter = DeepLinkRouter(),
    backgroundRefreshCoordinator: BackgroundRefreshCoordinator? = nil
  ) {
    self.engine = engine
    self.deepLinkRouter = deepLinkRouter
    self.backgroundRefreshCoordinator = backgroundRefreshCoordinator ?? BackgroundRefreshCoordinator()

    self.backgroundRefreshCoordinator.setRefreshHandler { [weak self] in
      await self?.replenishSchedule()
    }
  }

  public func requestPermissions() async {
    do {
      _ = try await engine.requestPermissions()
    } catch {
      lastErrorMessage = error.localizedDescription
    }
  }

  public func replenishSchedule() async {
    do {
      _ = try await engine.replenishSchedule()
    } catch {
      lastErrorMessage = error.localizedDescription
    }
  }

  public func handle(url: URL) {
    guard let route = deepLinkRouter.route(for: url) else {
      return
    }

    switch route {
    case let .reminder(reminderID):
      selectedReminderID = reminderID
      nagScreenReminderID = nil

    case let .snooze(reminderID, minutes):
      quickSnoozeSelection = (reminderID: reminderID, minutes: minutes)
      Task {
        try? await engine.handleNotificationAction(
          NotificationActionIDs.snooze(minutes: minutes),
          reminderID: reminderID
        )
      }

    case let .nagScreen(reminderID):
      nagScreenReminderID = reminderID
      selectedReminderID = reminderID
    }
  }

  public func handleNotificationAction(_ actionIdentifier: String, reminderID: String) async {
    do {
      try await engine.handleNotificationAction(actionIdentifier, reminderID: reminderID)
    } catch {
      lastErrorMessage = error.localizedDescription
    }
  }

  public func snooze(reminderID: String, minutes: Int) async {
    do {
      try await engine.handleNotificationAction(
        NotificationActionIDs.snooze(minutes: minutes),
        reminderID: reminderID
      )
      try await engine.replenishSchedule()
    } catch {
      lastErrorMessage = error.localizedDescription
    }
  }

  public func markDone(reminderID: String) async {
    do {
      try await engine.handleNotificationAction(
        NotificationActionIDs.markDone,
        reminderID: reminderID
      )
    } catch {
      lastErrorMessage = error.localizedDescription
    }
  }

  public func stopNagging(reminderID: String) async {
    do {
      try await engine.handleNotificationAction(
        NotificationActionIDs.stopNagging,
        reminderID: reminderID
      )
    } catch {
      lastErrorMessage = error.localizedDescription
    }
  }

  public func dismissNagScreen() {
    nagScreenReminderID = nil
  }

  public func clearQuickSnoozeSelection() {
    quickSnoozeSelection = nil
  }

  public func activateBackgroundRefresh() {
    #if os(iOS)
    backgroundRefreshCoordinator.registerBGTask()
    backgroundRefreshCoordinator.scheduleNextBackgroundRefresh()
    #else
    backgroundRefreshCoordinator.startMacOSTimer()
    #endif
  }
}
