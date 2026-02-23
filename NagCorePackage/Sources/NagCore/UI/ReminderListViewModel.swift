import Foundation

@MainActor
public final class ReminderListViewModel: ObservableObject {
  @Published public private(set) var reminders: [ReminderItem] = []
  @Published public var selectedSmartList: SmartList = .today
  @Published public var searchText = ""
  @Published public var isLoading = false
  @Published public var errorMessage: String?
  @Published public var nagPolicy: NagPolicy = .default
  @Published public private(set) var nagStates: [String: Bool] = [:]
  @Published public private(set) var lists: [ReminderList] = []

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
      lists = try await remindersRepository.fetchLists()
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }
    loadNagStates()
  }

  public func loadNagStates() {
    guard nagPolicy.nagMode == .perReminder, let store = policyStore else {
      nagStates = [:]
      return
    }
    let policies = store.allPoliciesByReminderID()
    nagStates = policies.mapValues(\.isEnabled)
  }

  public func toggleNag(for reminder: ReminderItem) {
    guard let store = policyStore else { return }
    let current = nagStates[reminder.id] ?? false
    var policy = store.policy(for: reminder.id) ?? nagPolicy
    policy.isEnabled = !current
    try? store.save(policy, for: reminder.id)
    nagStates[reminder.id] = !current
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
