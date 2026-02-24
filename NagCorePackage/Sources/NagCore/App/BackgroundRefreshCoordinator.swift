import Foundation

#if canImport(BackgroundTasks)
import BackgroundTasks
#endif

@MainActor
public final class BackgroundRefreshCoordinator {
  public typealias RefreshHandler = @Sendable () async -> Void

  private let taskIdentifier: String
  private let refreshInterval: TimeInterval
  private var refreshHandler: RefreshHandler?
  private var macOSTimer: Timer?

  public init(
    taskIdentifier: String = "com.nudge.app.refresh",
    refreshInterval: TimeInterval = 15 * 60
  ) {
    self.taskIdentifier = taskIdentifier
    self.refreshInterval = refreshInterval
  }

  public func setRefreshHandler(_ handler: RefreshHandler?) {
    refreshHandler = handler
  }

  #if os(iOS)
  public func registerBGTask() {
    BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { [weak self] task in
      guard let appRefreshTask = task as? BGAppRefreshTask else {
        task.setTaskCompleted(success: false)
        return
      }

      self?.handle(task: appRefreshTask)
    }
  }

  public func scheduleNextBackgroundRefresh() {
    let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
    request.earliestBeginDate = Date(timeIntervalSinceNow: refreshInterval)

    do {
      try BGTaskScheduler.shared.submit(request)
    } catch {
      // Best effort by design. iOS may reject requests due to system heuristics.
    }
  }

  private func handle(task: BGAppRefreshTask) {
    scheduleNextBackgroundRefresh()

    task.expirationHandler = {
      task.setTaskCompleted(success: false)
    }

    Task {
      await refreshHandler?()
      task.setTaskCompleted(success: true)
    }
  }
  #else
  public func startMacOSTimer() {
    stopMacOSTimer()

    macOSTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
      Task {
        await self?.refreshHandler?()
      }
    }
  }

  public func stopMacOSTimer() {
    macOSTimer?.invalidate()
    macOSTimer = nil
  }
  #endif
}
