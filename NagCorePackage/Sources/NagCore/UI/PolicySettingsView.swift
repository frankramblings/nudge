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

      Section("Quiet Hours") {
        Toggle("Enable Quiet Hours", isOn: $policy.quietHoursEnabled)

        if policy.quietHoursEnabled {
          Stepper(value: $policy.quietHoursStartHour, in: 0...23) {
            Text("Start: \(policy.quietHoursStartHour):00")
          }
          Stepper(value: $policy.quietHoursEndHour, in: 0...23) {
            Text("End: \(policy.quietHoursEndHour):00")
          }
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
