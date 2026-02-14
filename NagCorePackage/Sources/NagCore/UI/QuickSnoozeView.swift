import SwiftUI

public struct QuickSnoozeView: View {
  private let title: String
  private let presets: [Int]
  private let onSnooze: (Int) -> Void
  private let onMarkDone: () -> Void
  private let onStopNagging: () -> Void

  public init(
    title: String,
    presets: [Int],
    onSnooze: @escaping (Int) -> Void,
    onMarkDone: @escaping () -> Void,
    onStopNagging: @escaping () -> Void
  ) {
    self.title = title
    self.presets = presets
    self.onSnooze = onSnooze
    self.onMarkDone = onMarkDone
    self.onStopNagging = onStopNagging
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text(title)
        .font(.title2.weight(.bold))

      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
        ForEach(presets, id: \.self) { minutes in
          Button("\(minutes) min") {
            onSnooze(minutes)
          }
          .buttonStyle(.borderedProminent)
        }
      }

      HStack {
        Button("Mark Done", action: onMarkDone)
          .buttonStyle(.bordered)

        Spacer()

        Button("Stop Nagging", role: .destructive, action: onStopNagging)
          .buttonStyle(.bordered)
      }
    }
    .padding()
    .presentationDetents([.medium])
  }
}
