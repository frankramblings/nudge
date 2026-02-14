import SwiftUI

public struct ReminderListView: View {
  private let reminders: [ReminderItem]
  private let onToggleCompletion: (ReminderItem) -> Void
  private let onQuickSnooze: (ReminderItem) -> Void
  private let onDelete: (ReminderItem) -> Void

  public init(
    reminders: [ReminderItem],
    onToggleCompletion: @escaping (ReminderItem) -> Void,
    onQuickSnooze: @escaping (ReminderItem) -> Void,
    onDelete: @escaping (ReminderItem) -> Void
  ) {
    self.reminders = reminders
    self.onToggleCompletion = onToggleCompletion
    self.onQuickSnooze = onQuickSnooze
    self.onDelete = onDelete
  }

  public var body: some View {
    List {
      ForEach(reminders) { reminder in
        ReminderRowView(
          reminder: reminder,
          onToggleComplete: { onToggleCompletion(reminder) },
          onQuickSnooze: { onQuickSnooze(reminder) }
        )
        .swipeActions(allowsFullSwipe: true) {
          Button(role: .destructive) {
            onDelete(reminder)
          } label: {
            Label("Delete", systemImage: "trash")
          }

          Button {
            onQuickSnooze(reminder)
          } label: {
            Label("Snooze", systemImage: "clock")
          }
          .tint(.blue)
        }
      }
    }
  }
}
