import SwiftUI

public struct InlineNagSettingsView: View {
  @Binding var policy: NagPolicy

  public init(policy: Binding<NagPolicy>) {
    _policy = policy
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Toggle("Nag enabled", isOn: $policy.isEnabled)

      if policy.isEnabled {
        Stepper(value: $policy.intervalMinutes, in: 1...120) {
          Text("Every \(policy.intervalMinutes) min")
            .font(.subheadline)
        }

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
              .font(.subheadline)
          }

          Stepper(value: Binding(
            get: { policy.escalationIntervalMinutes ?? 2 },
            set: { policy.escalationIntervalMinutes = $0 }
          ), in: 1...60) {
            Text("Then every \(policy.escalationIntervalMinutes ?? 2) min")
              .font(.subheadline)
          }
        }
      }
    }
    .padding(.vertical, 4)
    .font(.subheadline)
  }
}
