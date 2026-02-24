import SwiftUI

public struct InlineNagSettingsView: View {
  @Binding var policy: NagPolicy

  public init(policy: Binding<NagPolicy>) {
    _policy = policy
  }

  public var body: some View {
    VStack(spacing: 16) {
      Toggle("Nag enabled", isOn: $policy.isEnabled)

      if policy.isEnabled {
        Divider()

        Stepper(value: $policy.intervalMinutes, in: 1...120) {
          Text("Every \(policy.intervalMinutes) min")
        }

        Divider()

        Toggle("Escalate", isOn: Binding(
          get: { policy.escalationAfterNags != nil },
          set: { policy.escalationAfterNags = $0 ? 5 : nil; policy.escalationIntervalMinutes = $0 ? 2 : nil }
        ))

        if policy.escalationAfterNags != nil {
          Stepper(value: Binding(
            get: { policy.escalationAfterNags ?? 5 },
            set: { policy.escalationAfterNags = $0 }
          ), in: 1...50) {
            Text("After \(policy.escalationAfterNags ?? 5) nags")
          }

          Stepper(value: Binding(
            get: { policy.escalationIntervalMinutes ?? 2 },
            set: { policy.escalationIntervalMinutes = $0 }
          ), in: 1...60) {
            Text("Then every \(policy.escalationIntervalMinutes ?? 2) min")
          }
        }
      }
    }
    .font(.subheadline)
  }
}
