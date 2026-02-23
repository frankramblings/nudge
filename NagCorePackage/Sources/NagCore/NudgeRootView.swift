import SwiftUI

public struct NudgeRootView: View {
  private let repository: (any RemindersRepository)?
  private let policyStore: (any NagPolicyStore)?

  public init(
    repository: (any RemindersRepository)? = nil,
    policyStore: (any NagPolicyStore)? = nil
  ) {
    self.repository = repository
    self.policyStore = policyStore
  }

  public var body: some View {
    ReminderDashboardView(repository: repository, policyStore: policyStore)
  }
}
