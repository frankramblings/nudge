import SwiftUI

public struct ReminderRowView: View {
  private let reminder: ReminderItem
  private let onToggleComplete: () -> Void
  private let onQuickSnooze: () -> Void

  public init(
    reminder: ReminderItem,
    onToggleComplete: @escaping () -> Void,
    onQuickSnooze: @escaping () -> Void
  ) {
    self.reminder = reminder
    self.onToggleComplete = onToggleComplete
    self.onQuickSnooze = onQuickSnooze
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

      Button("Snooze", action: onQuickSnooze)
        .buttonStyle(.bordered)
        .font(.caption)
    }
    .padding(.vertical, 4)
  }
}
