import EventKit
import Foundation

public final class EventKitRemindersRepository: RemindersRepository {
  private let eventStore: EKEventStore
  private let notificationCenter: NotificationCenter
  private var storeChangedHandler: (@Sendable () -> Void)?
  private var observer: NSObjectProtocol?

  private static let nudgeListKey = "com.nudge.listID"

  public init(
    eventStore: EKEventStore = EKEventStore(),
    notificationCenter: NotificationCenter = .default
  ) {
    self.eventStore = eventStore
    self.notificationCenter = notificationCenter
  }

  deinit {
    if let observer {
      notificationCenter.removeObserver(observer)
    }
  }

  public func requestAccess() async throws -> Bool {
    try await eventStore.requestFullAccessToReminders()
  }

  public func ensureNudgeList() async throws -> String {
    if let existingID = UserDefaults.standard.string(forKey: Self.nudgeListKey),
       eventStore.calendar(withIdentifier: existingID) != nil {
      return existingID
    }

    // Check if a list named "Nudge" already exists
    if let existing = eventStore.calendars(for: .reminder).first(where: { $0.title == "Nudge" }) {
      UserDefaults.standard.set(existing.calendarIdentifier, forKey: Self.nudgeListKey)
      return existing.calendarIdentifier
    }

    let calendar = EKCalendar(for: .reminder, eventStore: eventStore)
    calendar.title = "Nudge"
    calendar.source = eventStore.defaultCalendarForNewReminders()?.source
    try eventStore.saveCalendar(calendar, commit: true)
    UserDefaults.standard.set(calendar.calendarIdentifier, forKey: Self.nudgeListKey)
    return calendar.calendarIdentifier
  }

  public func fetchLists() async throws -> [ReminderList] {
    eventStore
      .calendars(for: .reminder)
      .map { ReminderList(id: $0.calendarIdentifier, title: $0.title) }
      .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
  }

  public func fetchReminders(inList listID: String) async throws -> [ReminderItem] {
    guard let calendar = eventStore.calendar(withIdentifier: listID) else {
      return []
    }
    let predicate = eventStore.predicateForReminders(in: [calendar])
    let reminders = try await fetchReminders(matching: predicate)
    return reminders
      .map(mapReminder)
      .filter { !$0.isCompleted }
      .sorted(byDueDate: true)
  }

  public func fetchAllReminders() async throws -> [ReminderItem] {
    let predicate = eventStore.predicateForReminders(in: nil)
    let reminders = try await fetchReminders(matching: predicate)
    return reminders
      .map(mapReminder)
      .filter { !$0.isCompleted }
      .sorted(byDueDate: true)
  }

  public func saveReminder(_ draft: ReminderDraft) async throws -> ReminderItem {
    let reminder = try reminderForSave(draft: draft)

    reminder.title = draft.title
    reminder.notes = draft.notes
    reminder.isCompleted = draft.isCompleted
    reminder.priority = draft.priority

    if let dueDate = draft.dueDate {
      if draft.hasTimeComponent {
        reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
      } else {
        reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: dueDate)
      }
    } else {
      reminder.dueDateComponents = nil
    }

    reminder.calendar = eventStore.calendar(withIdentifier: draft.listID) ?? eventStore.defaultCalendarForNewReminders()

    try eventStore.save(reminder, commit: true)
    return mapReminder(reminder)
  }

  public func setCompleted(reminderID: String, isCompleted: Bool) async throws {
    guard let reminder = eventStore.calendarItem(withIdentifier: reminderID) as? EKReminder else {
      return
    }

    reminder.isCompleted = isCompleted
    try eventStore.save(reminder, commit: true)
  }

  public func deleteReminder(id: String) async throws {
    guard let reminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder else {
      return
    }

    try eventStore.remove(reminder, commit: true)
  }

  public func moveReminder(id: String, to listID: String) async throws {
    guard let reminder = eventStore.calendarItem(withIdentifier: id) as? EKReminder,
          let calendar = eventStore.calendar(withIdentifier: listID) else {
      return
    }

    reminder.calendar = calendar
    try eventStore.save(reminder, commit: true)
  }

  public func setStoreChangedHandler(_ handler: (@Sendable () -> Void)?) {
    storeChangedHandler = handler

    if let observer {
      notificationCenter.removeObserver(observer)
      self.observer = nil
    }

    guard handler != nil else {
      return
    }

    observer = notificationCenter.addObserver(
      forName: .EKEventStoreChanged,
      object: eventStore,
      queue: .main
    ) { [weak self] _ in
      self?.storeChangedHandler?()
    }
  }

  private func reminderForSave(draft: ReminderDraft) throws -> EKReminder {
    if let id = draft.id,
       let existing = eventStore.calendarItem(withIdentifier: id) as? EKReminder {
      return existing
    }

    guard let defaultCalendar = eventStore.defaultCalendarForNewReminders() else {
      throw NSError(domain: "EventKitRemindersRepository", code: 1)
    }

    let reminder = EKReminder(eventStore: eventStore)
    reminder.calendar = defaultCalendar
    return reminder
  }

  private func fetchReminders(matching predicate: NSPredicate) async throws -> [EKReminder] {
    try await withCheckedThrowingContinuation { continuation in
      eventStore.fetchReminders(matching: predicate) { reminders in
        continuation.resume(returning: reminders ?? [])
      }
    }
  }

  private func mapReminder(_ reminder: EKReminder) -> ReminderItem {
    let dueDate = reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
    let hasTimeComponent = reminder.dueDateComponents?.hour != nil || reminder.dueDateComponents?.minute != nil

    return ReminderItem(
      id: reminder.calendarItemIdentifier,
      title: reminder.title,
      notes: reminder.notes,
      dueDate: dueDate,
      isCompleted: reminder.isCompleted,
      isFlagged: reminder.priority > 5,
      priority: reminder.priority,
      listID: reminder.calendar.calendarIdentifier,
      listTitle: reminder.calendar.title,
      hasTimeComponent: hasTimeComponent
    )
  }
}

private extension Array where Element == ReminderItem {
  func sorted(byDueDate ascending: Bool) -> [ReminderItem] {
    sorted { lhs, rhs in
      switch (lhs.dueDate, rhs.dueDate) {
      case let (lhsDate?, rhsDate?):
        return ascending ? lhsDate < rhsDate : lhsDate > rhsDate
      case (_?, nil):
        return true
      case (nil, _?):
        return false
      case (nil, nil):
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
      }
    }
  }
}
