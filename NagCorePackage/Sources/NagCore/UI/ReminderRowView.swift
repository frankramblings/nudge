import SwiftUI

public struct ReminderRowView: View {
  private let reminder: ReminderItem
  private let isNagging: Bool
  @Binding private var policy: NagPolicy
  private let isExpanded: Bool
  private let onToggleComplete: () -> Void
  private let onQuickSnooze: () -> Void
  private let onTap: () -> Void
  private let onSavePolicy: () -> Void

  public init(
    reminder: ReminderItem,
    isNagging: Bool,
    policy: Binding<NagPolicy>,
    isExpanded: Bool,
    onToggleComplete: @escaping () -> Void,
    onQuickSnooze: @escaping () -> Void,
    onTap: @escaping () -> Void,
    onSavePolicy: @escaping () -> Void
  ) {
    self.reminder = reminder
    self.isNagging = isNagging
    _policy = policy
    self.isExpanded = isExpanded
    self.onToggleComplete = onToggleComplete
    self.onQuickSnooze = onQuickSnooze
    self.onTap = onTap
    self.onSavePolicy = onSavePolicy
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
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

          if let dueDate = reminder.dueDate {
            Text(dueDate, style: .relative)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        Spacer(minLength: 0)

        Image(systemName: isNagging ? "bell.fill" : "bell.slash")
          .foregroundStyle(isNagging ? .orange : .secondary)
      }
      .padding(.vertical, 4)
      .contentShape(Rectangle())
      .onTapGesture(perform: onTap)

      if isExpanded {
        Divider()
          .padding(.vertical, 4)

        InlineNagSettingsView(policy: $policy)
          .onChange(of: policy) { _, _ in onSavePolicy() }

        Button("Snooze", action: onQuickSnooze)
          .buttonStyle(.bordered)
          .font(.caption)
          .padding(.top, 4)
      }
    }
  }
}
