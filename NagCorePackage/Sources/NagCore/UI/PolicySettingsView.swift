import SwiftUI

public struct PolicySettingsView: View {
  @Binding private var policy: NagPolicy

  public init(policy: Binding<NagPolicy>) {
    _policy = policy
  }

  public var body: some View {
    Form {
      Section("Repeating Alerts") {
        Toggle("Enable Nagging", isOn: $policy.isEnabled)

        Stepper(value: $policy.intervalMinutes, in: 1...120) {
          Text("Interval: \(policy.intervalMinutes) min")
        }

        Stepper(value: $policy.repeatAtLeast, in: 1...100) {
          Text("Repeat At Least: \(policy.repeatAtLeast)")
        }

        Picker("Repeat Mode", selection: $policy.repeatIndefinitelyMode) {
          Text("Off").tag(RepeatIndefinitelyMode.off)
          Text("When Possible").tag(RepeatIndefinitelyMode.whenPossible)
          Text("Always").tag(RepeatIndefinitelyMode.always)
        }
      }

      Section("Escalation") {
        Toggle("Enable Escalation", isOn: Binding(
          get: { policy.escalationAfterNags != nil },
          set: { policy.escalationAfterNags = $0 ? 5 : nil; policy.escalationIntervalMinutes = $0 ? 2 : nil }
        ))

        if let _ = policy.escalationAfterNags {
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
            Text("Escalated interval: \(policy.escalationIntervalMinutes ?? 2) min")
          }
        }
      }

      Section("Nag Mode") {
        Picker("Mode", selection: $policy.nagMode) {
          Text("Per Reminder").tag(NagMode.perReminder)
          Text("Per List").tag(NagMode.perList)
        }
      }

      Section("Date-only Due Items") {
        Stepper(value: $policy.dateOnlyDueHour, in: 0...23) {
          Text("Treat date-only reminders as due at \(policy.dateOnlyDueHour):00")
        }
      }
    }
    .formStyle(.grouped)
  }
}
