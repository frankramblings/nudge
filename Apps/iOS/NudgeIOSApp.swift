import NagCore
import SwiftData
import SwiftUI

@MainActor
private final class IOSAppDependencies: ObservableObject {
  let modelContainer: ModelContainer
  let remindersRepository: EventKitRemindersRepository
  let appController: NagAppController

  init() {
    do {
      modelContainer = try ModelContainer(for: NagPolicyRecord.self, NagSessionRecord.self)
    } catch {
      fatalError("Unable to create SwiftData model container: \(error)")
    }

    remindersRepository = EventKitRemindersRepository()

    let policyStore = SwiftDataNagPolicyStore(context: modelContainer.mainContext)
    let sessionStore = SwiftDataNagSessionStore(context: modelContainer.mainContext)
    let notificationClient = UserNotificationClient()

    let engine = NagEngine(
      remindersRepository: remindersRepository,
      policyStore: policyStore,
      sessionStore: sessionStore,
      notificationClient: notificationClient
    )

    appController = NagAppController(engine: engine)
  }
}

@main
struct NudgeIOSApp: App {
  @StateObject private var dependencies = IOSAppDependencies()

  var body: some Scene {
    WindowGroup {
      NavigationStack {
        NudgeRootView(repository: dependencies.remindersRepository)
      }
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
    }
  }
}
