import Foundation

public final class MockRemindersRepository: RemindersRepository {
  public private(set) var completedReminderIDs: [String] = []

  private var reminders: [ReminderItem]
  private var storeChangedHandler: (@Sendable () -> Void)?

  public init(reminders: [ReminderItem] = MockRemindersRepository.defaultReminders()) {
    self.reminders = reminders
  }

  public func requestAccess() async throws -> Bool {
    true
  }

  public func fetchLists() async throws -> [ReminderList] {
    let grouped = Dictionary(grouping: reminders, by: \.listID)
    return grouped
      .map { listID, reminders in
        ReminderList(id: listID, title: reminders.first?.listTitle ?? "List")
      }
      .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
  }

  public func fetchReminders(in smartList: SmartList) async throws -> [ReminderItem] {
    reminders
      .filtered(for: smartList)
      .sorted { lhs, rhs in
        switch (lhs.dueDate, rhs.dueDate) {
        case let (lhsDate?, rhsDate?):
          return lhsDate < rhsDate
        case (nil, _?):
          return false
        case (_?, nil):
          return true
        case (nil, nil):
          return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
      }
  }

  public func saveReminder(_ draft: ReminderDraft) async throws -> ReminderItem {
    let reminderID = draft.id ?? UUID().uuidString
    let listTitle = reminders.first(where: { $0.listID == draft.listID })?.listTitle ?? "Reminders"

    let reminder = ReminderItem(
      id: reminderID,
      title: draft.title,
      notes: draft.notes,
      dueDate: draft.dueDate,
      isCompleted: draft.isCompleted,
      isFlagged: draft.isFlagged,
      priority: draft.priority,
      listID: draft.listID,
      listTitle: listTitle,
      hasTimeComponent: draft.hasTimeComponent
    )

    if let existingIndex = reminders.firstIndex(where: { $0.id == reminderID }) {
      reminders[existingIndex] = reminder
    } else {
      reminders.append(reminder)
    }

    storeChangedHandler?()
    return reminder
  }

  public func setCompleted(reminderID: String, isCompleted: Bool) async throws {
    if let index = reminders.firstIndex(where: { $0.id == reminderID }) {
      reminders[index].isCompleted = isCompleted
    }
    if isCompleted {
      completedReminderIDs.append(reminderID)
    }
    storeChangedHandler?()
  }

  public func deleteReminder(id: String) async throws {
    reminders.removeAll { $0.id == id }
    storeChangedHandler?()
  }

  public func moveReminder(id: String, to listID: String) async throws {
    guard let index = reminders.firstIndex(where: { $0.id == id }) else {
      return
    }

    reminders[index].listID = listID
    reminders[index].listTitle = "Moved"
    storeChangedHandler?()
  }

  public func setStoreChangedHandler(_ handler: (@Sendable () -> Void)?) {
    storeChangedHandler = handler
  }

  public func simulateStoreChange() {
    storeChangedHandler?()
  }

  public static func sampleData() -> MockRemindersRepository {
    MockRemindersRepository(reminders: defaultReminders())
  }

  public static func defaultReminders() -> [ReminderItem] {
    let now = Date()
    return [
      ReminderItem(
        id: "sample-1",
        title: "Check in with Alex",
        notes: "Discuss sprint scope",
        dueDate: now.addingTimeInterval(-30 * 60),
        isCompleted: false,
        isFlagged: true,
        priority: 1,
        listID: "work",
        listTitle: "Work",
        hasTimeComponent: true
      ),
      ReminderItem(
        id: "sample-2",
        title: "Bring package to post office",
        notes: nil,
        dueDate: now.addingTimeInterval(2 * 60 * 60),
        isCompleted: false,
        isFlagged: false,
        priority: 0,
        listID: "home",
        listTitle: "Home",
        hasTimeComponent: true
      ),
      ReminderItem(
        id: "sample-3",
        title: "Book dentist appointment",
        notes: nil,
        dueDate: now.addingTimeInterval(-24 * 60 * 60),
        isCompleted: true,
        isFlagged: false,
        priority: 0,
        listID: "personal",
        listTitle: "Personal",
        hasTimeComponent: false
      ),
    ]
  }
}
