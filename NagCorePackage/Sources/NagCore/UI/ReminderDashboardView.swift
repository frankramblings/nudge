import SwiftUI

public struct ReminderDashboardView: View {
  @StateObject private var viewModel: ReminderListViewModel
  @State private var quickSnoozeReminder: ReminderItem?
  @State private var showSettings = false
  @State private var showNagScreen = false

  private let debugNotificationsEnabled: Bool

  public init(
    repository: (any RemindersRepository)? = nil,
    policyStore: (any NagPolicyStore)? = nil
  ) {
    _viewModel = StateObject(
      wrappedValue: ReminderListViewModel(
        remindersRepository: repository ?? MockRemindersRepository.sampleData(),
        policyStore: policyStore
      )
    )

    debugNotificationsEnabled = ProcessInfo.processInfo.arguments.contains("--ui-test-debug-notifications")
  }

  public var body: some View {
    NavigationStack {
      VStack(spacing: 12) {
        Picker("Smart List", selection: $viewModel.selectedSmartList) {
          ForEach(SmartList.allCases) { smartList in
            Text(smartList.rawValue)
              .tag(smartList)
          }
        }
        .pickerStyle(.segmented)

        if let errorMessage = viewModel.errorMessage {
          Text(errorMessage)
            .font(.footnote)
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        ReminderListView(
          reminders: viewModel.visibleReminders,
          onToggleCompletion: { reminder in
            Task { await viewModel.toggleCompletion(for: reminder) }
          },
          onQuickSnooze: { reminder in
            quickSnoozeReminder = reminder
          },
          onDelete: { reminder in
            Task { await viewModel.delete(reminder) }
          }
        )
      }
      .padding(.horizontal)
      .searchable(text: $viewModel.searchText)
      .navigationTitle("Nudge")
      .toolbar {
        ToolbarItem {
          Button("Settings") {
            showSettings = true
          }
        }

        ToolbarItem {
          Button {
            Task { await viewModel.addReminder(title: "New Reminder") }
          } label: {
            Image(systemName: "plus")
          }
        }
      }
      .overlay {
        if viewModel.isLoading {
          ProgressView()
        }
      }
      .task {
        await viewModel.refresh()
      }
      .onChange(of: viewModel.selectedSmartList) { _, _ in
        Task {
          await viewModel.refresh()
        }
      }
      .sheet(item: $quickSnoozeReminder) { reminder in
        QuickSnoozeView(
          title: reminder.title,
          presets: viewModel.nagPolicy.snoozePresetMinutes,
          onSnooze: { minutes in
            Task { await viewModel.snooze(reminder, minutes: minutes) }
            quickSnoozeReminder = nil
          },
          onMarkDone: {
            Task { await viewModel.toggleCompletion(for: reminder) }
            quickSnoozeReminder = nil
          },
          onStopNagging: {
            quickSnoozeReminder = nil
          }
        )
      }
      .sheet(isPresented: $showSettings) {
        NavigationStack {
          PolicySettingsView(policy: $viewModel.nagPolicy)
            .navigationTitle("Nag Settings")
            .toolbar {
              ToolbarItem {
                Button("Done") {
                  viewModel.savePolicy()
                  showSettings = false
                }
              }
            }
        }
      }
      .sheet(isPresented: $showNagScreen) {
        NagScreenView(
          title: "Debug Reminder",
          onSnooze: { showNagScreen = false },
          onStop: { showNagScreen = false }
        )
      }
      .safeAreaInset(edge: .bottom) {
        if debugNotificationsEnabled {
          debugPanel
        }
      }
    }
  }

  private var debugPanel: some View {
    HStack(spacing: 12) {
      Button("Simulate Nag") {
        showNagScreen = true
      }
      .buttonStyle(.borderedProminent)
      .accessibilityIdentifier("debug.simulateNagDelivery")

      Button("Simulate Action") {
        quickSnoozeReminder = viewModel.visibleReminders.first ?? ReminderItem(
          id: "debug-reminder",
          title: "Debug Reminder",
          notes: nil,
          dueDate: Date(),
          isCompleted: false,
          isFlagged: false,
          priority: 0,
          listID: "debug",
          listTitle: "Debug",
          hasTimeComponent: true
        )
      }
      .buttonStyle(.bordered)
      .accessibilityIdentifier("debug.simulateNotificationAction")
    }
    .padding(.horizontal)
    .padding(.bottom, 8)
  }
}
