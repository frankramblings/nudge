import SwiftUI

public struct NagScreenView: View {
  private let title: String
  private let onSnooze: () -> Void
  private let onStop: () -> Void

  public init(
    title: String,
    onSnooze: @escaping () -> Void,
    onStop: @escaping () -> Void
  ) {
    self.title = title
    self.onSnooze = onSnooze
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

        Button("Snooze 10 Minutes", action: onSnooze)
          .buttonStyle(.borderedProminent)
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
