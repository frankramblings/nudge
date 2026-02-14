import Foundation

public protocol RemindersRepository: AnyObject {
  func requestAccess() async throws -> Bool
  func fetchLists() async throws -> [ReminderList]
  func fetchReminders(in smartList: SmartList) async throws -> [ReminderItem]
  func saveReminder(_ draft: ReminderDraft) async throws -> ReminderItem
  func setCompleted(reminderID: String, isCompleted: Bool) async throws
  func deleteReminder(id: String) async throws
  func moveReminder(id: String, to listID: String) async throws
  func setStoreChangedHandler(_ handler: (@Sendable () -> Void)?)
}

public extension Array where Element == ReminderItem {
  func filtered(for smartList: SmartList, now: Date = Date(), calendar: Calendar = .current) -> [ReminderItem] {
    switch smartList {
    case .today:
      return filter {
        guard let dueDate = $0.dueDate else {
          return false
        }

        return calendar.isDateInToday(dueDate) && !$0.isCompleted
      }
    case .scheduled:
      return filter { $0.dueDate != nil && !$0.isCompleted }
    case .all:
      return filter { !$0.isCompleted }
    case .flagged:
      return filter { $0.isFlagged && !$0.isCompleted }
    case .completed:
      return filter { $0.isCompleted }
    }
  }
}
