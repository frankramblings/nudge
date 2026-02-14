import SwiftUI
import NagCore

@main
struct NagRemindersMacApp: App {
  var body: some Scene {
    WindowGroup {
      NagRootView()
        .frame(minWidth: 960, minHeight: 680)
    }
  }
}
