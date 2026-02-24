import Foundation

public protocol RemindersRepository: AnyObject {
  func requestAccess() async throws -> Bool
  func fetchLists() async throws -> [ReminderList]
  func fetchReminders(inList listID: String) async throws -> [ReminderItem]
  func fetchAllReminders() async throws -> [ReminderItem]
  func ensureNudgeList() async throws -> String
  func saveReminder(_ draft: ReminderDraft) async throws -> ReminderItem
  func setCompleted(reminderID: String, isCompleted: Bool) async throws
  func deleteReminder(id: String) async throws
  func moveReminder(id: String, to listID: String) async throws
  func setStoreChangedHandler(_ handler: (@Sendable () -> Void)?)
}
