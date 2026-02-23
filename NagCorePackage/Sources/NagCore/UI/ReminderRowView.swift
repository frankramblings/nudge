import SwiftUI

public struct ReminderRowView: View {
  private let reminder: ReminderItem
  private let isNagging: Bool?
  private let onToggleComplete: () -> Void
  private let onQuickSnooze: () -> Void
  private let onToggleNag: (() -> Void)?

  public init(
    reminder: ReminderItem,
    isNagging: Bool? = nil,
    onToggleComplete: @escaping () -> Void,
    onQuickSnooze: @escaping () -> Void,
    onToggleNag: (() -> Void)? = nil
  ) {
    self.reminder = reminder
    self.isNagging = isNagging
    self.onToggleComplete = onToggleComplete
    self.onQuickSnooze = onQuickSnooze
    self.onToggleNag = onToggleNag
  }

  public var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Button(action: onToggleComplete) {
        Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
          .imageScale(.large)
      }
      .buttonStyle(.plain)

      VStack(alignment: .leading, spacing: 6) {
        Text(reminder.title)
          .font(.headline)
          .foregroundStyle(reminder.isCompleted ? .secondary : .primary)
          .strikethrough(reminder.isCompleted, pattern: .solid)

        if let notes = reminder.notes, !notes.isEmpty {
          Text(notes)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }

        HStack(spacing: 8) {
          Text(reminder.listTitle)
            .font(.caption)
            .foregroundStyle(.secondary)

          if let dueDate = reminder.dueDate {
            Text(dueDate, style: .relative)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
      }

      Spacer(minLength: 0)

      if let isNagging, let onToggleNag {
        Button(action: onToggleNag) {
          Image(systemName: isNagging ? "bell.fill" : "bell.slash")
            .foregroundStyle(isNagging ? .orange : .secondary)
        }
        .buttonStyle(.plain)
      }

      Button("Snooze", action: onQuickSnooze)
        .buttonStyle(.bordered)
        .font(.caption)
    }
    .padding(.vertical, 4)
  }
}
