import SwiftUI

public struct NagScreenView: View {
  private let title: String
  private let snoozePresets: [Int]
  private let onSnooze: (Int) -> Void
  private let onMarkDone: () -> Void
  private let onStop: () -> Void

  public init(
    title: String,
    snoozePresets: [Int] = [5, 10, 20],
    onSnooze: @escaping (Int) -> Void,
    onMarkDone: @escaping () -> Void = {},
    onStop: @escaping () -> Void
  ) {
    self.title = title
    self.snoozePresets = snoozePresets
    self.onSnooze = onSnooze
    self.onMarkDone = onMarkDone
    self.onStop = onStop
  }

  public var body: some View {
    ZStack {
      LinearGradient(
        colors: [Color.red.opacity(0.3), Color.orange.opacity(0.35)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .ignoresSafeArea()

      VStack(spacing: 24) {
        Text("Overdue")
          .font(.title3.weight(.semibold))
          .textCase(.uppercase)
          .accessibilityIdentifier("nag.screen.title")

        Text(title)
          .font(.largeTitle.weight(.bold))
          .multilineTextAlignment(.center)

        ForEach(snoozePresets, id: \.self) { minutes in
          Button("Snooze \(minutes) Minutes") { onSnooze(minutes) }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }

        Button("Mark Done", action: onMarkDone)
          .buttonStyle(.bordered)
          .controlSize(.large)

        Button("Stop Nagging", role: .destructive, action: onStop)
          .buttonStyle(.bordered)
          .controlSize(.large)
      }
      .padding(28)
      .accessibilityIdentifier("nag.screen")
    }
  }
}
