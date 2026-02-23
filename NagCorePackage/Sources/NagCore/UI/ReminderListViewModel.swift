import Foundation

@MainActor
public final class ReminderListViewModel: ObservableObject {
  @Published public private(set) var reminders: [ReminderItem] = []
  @Published public var selectedSmartList: SmartList = .today
  @Published public var searchText = ""
  @Published public var isLoading = false
  @Published public var errorMessage: String?
  @Published public var nagPolicy: NagPolicy = .default

  private let remindersRepository: any RemindersRepository
  private let policyStore: (any NagPolicyStore)?

  public init(
    remindersRepository: any RemindersRepository = MockRemindersRepository.sampleData(),
    policyStore: (any NagPolicyStore)? = nil
  ) {
    self.remindersRepository = remindersRepository
    self.policyStore = policyStore
    if let store = policyStore {
      self.nagPolicy = store.globalPolicy()
    }
    self.remindersRepository.setStoreChangedHandler { [weak self] in
      Task {
        await self?.refresh()
      }
    }
  }

  public func savePolicy() {
    try? policyStore?.save(nagPolicy, for: nil)
  }

  public var visibleReminders: [ReminderItem] {
    guard !searchText.isEmpty else {
      return reminders
    }

    let query = searchText.lowercased()
    return reminders.filter {
      $0.title.lowercased().contains(query) || ($0.notes?.lowercased().contains(query) ?? false)
    }
  }

  public func refresh() async {
    isLoading = true
    defer { isLoading = false }

    do {
      reminders = try await remindersRepository.fetchReminders(in: selectedSmartList)
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  public func addReminder(title: String, listID: String = "inbox") async {
    let draft = ReminderDraft(
      title: title,
      dueDate: Date().addingTimeInterval(60 * 30),
      hasTimeComponent: true,
      listID: listID
    )

    do {
      _ = try await remindersRepository.saveReminder(draft)
      await refresh()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  public func toggleCompletion(for reminder: ReminderItem) async {
    do {
      try await remindersRepository.setCompleted(reminderID: reminder.id, isCompleted: !reminder.isCompleted)
      await refresh()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  public func delete(_ reminder: ReminderItem) async {
    do {
      try await remindersRepository.deleteReminder(id: reminder.id)
      await refresh()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  public func snooze(_ reminder: ReminderItem, minutes: Int) async {
    let date = Date().addingTimeInterval(Double(max(minutes, 1) * 60))
    let draft = ReminderDraft(
      id: reminder.id,
      title: reminder.title,
      notes: reminder.notes,
      dueDate: date,
      hasTimeComponent: true,
      isCompleted: reminder.isCompleted,
      isFlagged: reminder.isFlagged,
      priority: reminder.priority,
      listID: reminder.listID
    )

    do {
      _ = try await remindersRepository.saveReminder(draft)
      await refresh()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
