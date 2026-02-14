import NagCore
import SwiftData
import SwiftUI

@MainActor
private final class MacAppDependencies: ObservableObject {
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
struct NudgeMacApp: App {
  @StateObject private var dependencies = MacAppDependencies()

  var body: some Scene {
    WindowGroup {
      NavigationSplitView {
        NudgeRootView(repository: dependencies.remindersRepository)
      } detail: {
        NudgeRootView(repository: dependencies.remindersRepository)
      }
      .frame(minWidth: 960, minHeight: 680)
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
