import SwiftUI

public struct NudgeRootView: View {
  private let repository: (any RemindersRepository)?

  public init(repository: (any RemindersRepository)? = nil) {
    self.repository = repository
  }

  public var body: some View {
    ReminderDashboardView(repository: repository)
  }
}
