import Foundation

public struct ReminderList: Identifiable, Hashable, Sendable {
  public let id: String
  public var title: String
  public var cgColorData: Data?

  public init(id: String, title: String, cgColorData: Data? = nil) {
    self.id = id
    self.title = title
    self.cgColorData = cgColorData
  }
}

public struct ReminderItem: Identifiable, Hashable, Sendable {
  public let id: String
  public var title: String
  public var notes: String?
  public var dueDate: Date?
  public var isCompleted: Bool
  public var isFlagged: Bool
  public var priority: Int
  public var listID: String
  public var listTitle: String
  public var hasTimeComponent: Bool

  public init(
    id: String,
    title: String,
    notes: String?,
    dueDate: Date?,
    isCompleted: Bool,
    isFlagged: Bool,
    priority: Int,
    listID: String,
    listTitle: String,
    hasTimeComponent: Bool
  ) {
    self.id = id
    self.title = title
    self.notes = notes
    self.dueDate = dueDate
    self.isCompleted = isCompleted
    self.isFlagged = isFlagged
    self.priority = priority
    self.listID = listID
    self.listTitle = listTitle
    self.hasTimeComponent = hasTimeComponent
  }
}

public struct ReminderDraft: Sendable {
  public var id: String?
  public var title: String
  public var notes: String?
  public var dueDate: Date?
  public var hasTimeComponent: Bool
  public var isCompleted: Bool
  public var isFlagged: Bool
  public var priority: Int
  public var listID: String

  public init(
    id: String? = nil,
    title: String,
    notes: String? = nil,
    dueDate: Date? = nil,
    hasTimeComponent: Bool = false,
    isCompleted: Bool = false,
    isFlagged: Bool = false,
    priority: Int = 0,
    listID: String
  ) {
    self.id = id
    self.title = title
    self.notes = notes
    self.dueDate = dueDate
    self.hasTimeComponent = hasTimeComponent
    self.isCompleted = isCompleted
    self.isFlagged = isFlagged
    self.priority = priority
    self.listID = listID
  }
}

public enum SmartList: String, CaseIterable, Identifiable, Sendable {
  case upcoming = "Upcoming"
  case all = "All"

  public var id: String { rawValue }
}
