import SwiftUI

public struct ReminderListView: View {
  private let reminders: [ReminderItem]
  private let nagStates: [String: Bool]
  @Binding private var policies: [String: NagPolicy]
  private let globalPolicy: NagPolicy
  @Binding private var expandedReminderID: String?
  private let onToggleCompletion: (ReminderItem) -> Void
  private let onQuickSnooze: (ReminderItem) -> Void
  private let onDelete: (ReminderItem) -> Void
  private let onSavePolicy: (ReminderItem) -> Void

  public init(
    reminders: [ReminderItem],
    nagStates: [String: Bool],
    policies: Binding<[String: NagPolicy]>,
    globalPolicy: NagPolicy,
    expandedReminderID: Binding<String?>,
    onToggleCompletion: @escaping (ReminderItem) -> Void,
    onQuickSnooze: @escaping (ReminderItem) -> Void,
    onDelete: @escaping (ReminderItem) -> Void,
    onSavePolicy: @escaping (ReminderItem) -> Void
  ) {
    self.reminders = reminders
    self.nagStates = nagStates
    _policies = policies
    self.globalPolicy = globalPolicy
    _expandedReminderID = expandedReminderID
    self.onToggleCompletion = onToggleCompletion
    self.onQuickSnooze = onQuickSnooze
    self.onDelete = onDelete
    self.onSavePolicy = onSavePolicy
  }

  public var body: some View {
    List {
      ForEach(reminders) { reminder in
        ReminderRowView(
          reminder: reminder,
          isNagging: nagStates[reminder.id] ?? true,
          policy: Binding(
            get: { policies[reminder.id] ?? globalPolicy },
            set: { policies[reminder.id] = $0 }
          ),
          isExpanded: expandedReminderID == reminder.id,
          onToggleComplete: { onToggleCompletion(reminder) },
          onQuickSnooze: { onQuickSnooze(reminder) },
          onTap: {
            withAnimation(.easeInOut(duration: 0.25)) {
              expandedReminderID = expandedReminderID == reminder.id ? nil : reminder.id
            }
          },
          onSavePolicy: { onSavePolicy(reminder) }
        )
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
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
    .listStyle(.plain)
  }
}
