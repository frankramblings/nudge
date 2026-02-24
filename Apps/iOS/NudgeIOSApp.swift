import NagCore
import SwiftData
import SwiftUI
import UserNotifications

@MainActor
private final class IOSAppDependencies: ObservableObject {
  let modelContainer: ModelContainer
  let remindersRepository: EventKitRemindersRepository
  let policyStore: SwiftDataNagPolicyStore
  let appController: NagAppController
  let notificationDelegate: NagNotificationDelegate

  init() {
    do {
      modelContainer = try ModelContainer(for: NagPolicyRecord.self, NagSessionRecord.self)
    } catch {
      fatalError("Unable to create SwiftData model container: \(error)")
    }

    remindersRepository = EventKitRemindersRepository()

    let policyStore = SwiftDataNagPolicyStore(context: modelContainer.mainContext)
    self.policyStore = policyStore
    let sessionStore = SwiftDataNagSessionStore(context: modelContainer.mainContext)
    let notificationClient = UserNotificationClient()

    let engine = NagEngine(
      remindersRepository: remindersRepository,
      policyStore: policyStore,
      sessionStore: sessionStore,
      notificationClient: notificationClient
    )

    let appController = NagAppController(engine: engine)
    self.appController = appController

    notificationDelegate = NagNotificationDelegate(
      onAction: { actionIdentifier, reminderID in
        await appController.handleNotificationAction(actionIdentifier, reminderID: reminderID)
        await appController.replenishSchedule()
      },
      onOpenDeepLink: { url in
        Task { @MainActor in
          appController.handle(url: url)
        }
      }
    )

    UNUserNotificationCenter.current().delegate = notificationDelegate
  }
}

@main
struct NudgeIOSApp: App {
  @StateObject private var dependencies = IOSAppDependencies()
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup {
      NudgeRootView(
        repository: dependencies.remindersRepository,
        policyStore: dependencies.policyStore
      )
      .environmentObject(dependencies.appController)
      .modelContainer(dependencies.modelContainer)
      .task {
        await dependencies.appController.requestPermissions()
        await dependencies.appController.replenishSchedule()
        dependencies.appController.activateBackgroundRefresh()
      }
      .onOpenURL { url in
        dependencies.appController.handle(url: url)
      }
      .onChange(of: scenePhase) { _, newPhase in
        if newPhase == .active {
          Task {
            await dependencies.appController.replenishSchedule()
          }
        }
      }
    }
  }
}
