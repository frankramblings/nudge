import SwiftUI

public struct ReminderListView: View {
  private let reminders: [ReminderItem]
  private let nagStates: [String: Bool]
  private let onToggleCompletion: (ReminderItem) -> Void
  private let onQuickSnooze: (ReminderItem) -> Void
  private let onDelete: (ReminderItem) -> Void
  private let onToggleNag: ((ReminderItem) -> Void)?

  public init(
    reminders: [ReminderItem],
    nagStates: [String: Bool] = [:],
    onToggleCompletion: @escaping (ReminderItem) -> Void,
    onQuickSnooze: @escaping (ReminderItem) -> Void,
    onDelete: @escaping (ReminderItem) -> Void,
    onToggleNag: ((ReminderItem) -> Void)? = nil
  ) {
    self.reminders = reminders
    self.nagStates = nagStates
    self.onToggleCompletion = onToggleCompletion
    self.onQuickSnooze = onQuickSnooze
    self.onDelete = onDelete
    self.onToggleNag = onToggleNag
  }

  public var body: some View {
    List {
      ForEach(reminders) { reminder in
        ReminderRowView(
          reminder: reminder,
          isNagging: nagStates.isEmpty ? nil : nagStates[reminder.id] ?? false,
          onToggleComplete: { onToggleCompletion(reminder) },
          onQuickSnooze: { onQuickSnooze(reminder) },
          onToggleNag: onToggleNag.map { handler in { handler(reminder) } }
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
