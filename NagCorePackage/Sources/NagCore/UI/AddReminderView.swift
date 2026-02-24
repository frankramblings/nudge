import SwiftUI

public struct AddReminderView: View {
  @State private var title = ""
  @State private var dueDate = Date().addingTimeInterval(30 * 60)
  @State private var hasDueDate = true
  @State private var hasTimeComponent = true

  private let onAdd: (String, Date?, Bool) -> Void
  private let onCancel: () -> Void

  public init(
    onAdd: @escaping (String, Date?, Bool) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.onAdd = onAdd
    self.onCancel = onCancel
  }

  public var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("What needs doing?", text: $title)
            .font(.title3)
        }

        Section {
          Toggle("Due date", isOn: $hasDueDate)

          if hasDueDate {
            Toggle("Include time", isOn: $hasTimeComponent)

            if hasTimeComponent {
              DatePicker("When", selection: $dueDate)
            } else {
              DatePicker("When", selection: $dueDate, displayedComponents: .date)
            }
          }
        }
      }
      .navigationTitle("New Reminder")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onCancel)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Add") {
            let date = hasDueDate ? dueDate : nil
            onAdd(title.trimmingCharacters(in: .whitespacesAndNewlines), date, hasTimeComponent)
          }
          .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
  }
}
