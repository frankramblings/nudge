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
    DisclosureGroup(isExpanded: Binding(
      get: { isExpanded },
      set: { _ in onTap() }
    )) {
      // Expanded settings
      VStack(spacing: 0) {
        InlineNagSettingsView(policy: $policy)
          .onChange(of: policy) { _, _ in onSavePolicy() }
          .padding(.top, 12)
          .padding(.bottom, 16)

        Button(action: onQuickSnooze) {
          Label("Snooze", systemImage: "clock")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
      }
    } label: {
      HStack(spacing: 14) {
        Button(action: onToggleComplete) {
          Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
            .font(.title2)
            .foregroundStyle(reminder.isCompleted ? .green : .secondary)
        }
        .buttonStyle(.plain)

        VStack(alignment: .leading, spacing: 4) {
          Text(reminder.title)
            .font(.body)
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
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
        }

        Spacer(minLength: 0)

        Image(systemName: isNagging ? "bell.fill" : "bell.slash")
          .font(.subheadline)
          .foregroundStyle(isNagging ? .orange : .secondary.opacity(0.5))
      }
      .padding(.vertical, 4)
    }
  }
}
