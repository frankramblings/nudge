import SwiftUI

public struct ImportRemindersView: View {
  @State private var lists: [ReminderList] = []
  @State private var remindersByList: [String: [ReminderItem]] = [:]
  @State private var selectedIDs: Set<String> = []
  @State private var expandedListIDs: Set<String> = []
  @State private var isLoading = true

  private let nudgeListID: String
  private let fetchLists: () async -> [ReminderList]
  private let fetchAllReminders: () async -> [ReminderItem]
  private let onImport: ([String]) -> Void
  private let onCancel: () -> Void

  public init(
    nudgeListID: String,
    fetchLists: @escaping () async -> [ReminderList],
    fetchAllReminders: @escaping () async -> [ReminderItem],
    onImport: @escaping ([String]) -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.nudgeListID = nudgeListID
    self.fetchLists = fetchLists
    self.fetchAllReminders = fetchAllReminders
    self.onImport = onImport
    self.onCancel = onCancel
  }

  public var body: some View {
    NavigationStack {
      Group {
        if isLoading {
          ProgressView()
        } else if lists.isEmpty {
          ContentUnavailableView("No Other Lists", systemImage: "list.bullet", description: Text("All your reminders are in Nudge."))
        } else {
          List {
            ForEach(lists) { list in
              Section(isExpanded: Binding(
                get: { expandedListIDs.contains(list.id) },
                set: { expanded in
                  if expanded { expandedListIDs.insert(list.id) } else { expandedListIDs.remove(list.id) }
                }
              )) {
                ForEach(remindersByList[list.id] ?? []) { reminder in
                  Button {
                    if selectedIDs.contains(reminder.id) {
                      selectedIDs.remove(reminder.id)
                    } else {
                      selectedIDs.insert(reminder.id)
                    }
                  } label: {
                    HStack {
                      Image(systemName: selectedIDs.contains(reminder.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selectedIDs.contains(reminder.id) ? .blue : .secondary)
                      VStack(alignment: .leading) {
                        Text(reminder.title)
                        if let dueDate = reminder.dueDate {
                          Text(dueDate, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                      }
                    }
                  }
                  .tint(.primary)
                }
              } header: {
                Text(list.title)
              }
            }
          }
        }
      }
      .navigationTitle("Import Reminders")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", action: onCancel)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Import (\(selectedIDs.count))") {
            onImport(Array(selectedIDs))
          }
          .disabled(selectedIDs.isEmpty)
        }
      }
      .task {
        let allLists = await fetchLists()
        let allReminders = await fetchAllReminders()

        lists = allLists.filter { $0.id != nudgeListID }
        remindersByList = Dictionary(grouping: allReminders.filter { $0.listID != nudgeListID }, by: \.listID)
        expandedListIDs = Set(lists.map(\.id))
        isLoading = false
      }
    }
  }
}
