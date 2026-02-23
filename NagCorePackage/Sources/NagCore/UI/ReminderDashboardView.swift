import SwiftUI

public struct ReminderDashboardView: View {
  @StateObject private var viewModel: ReminderListViewModel
  @EnvironmentObject private var appController: NagAppController
  @State private var quickSnoozeReminder: ReminderItem?
  @State private var showSettings = false

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
            Task {
              await appController.markDone(reminderID: reminder.id)
              await viewModel.refresh()
            }
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
        Task { await viewModel.refresh() }
      }
      .sheet(item: $quickSnoozeReminder) { reminder in
        QuickSnoozeView(
          title: reminder.title,
          presets: viewModel.nagPolicy.snoozePresetMinutes,
          onSnooze: { minutes in
            Task {
              await appController.snooze(reminderID: reminder.id, minutes: minutes)
              await viewModel.refresh()
            }
            quickSnoozeReminder = nil
          },
          onMarkDone: {
            Task {
              await appController.markDone(reminderID: reminder.id)
              await viewModel.refresh()
            }
            quickSnoozeReminder = nil
          },
          onStopNagging: {
            Task {
              await appController.stopNagging(reminderID: reminder.id)
              await viewModel.refresh()
            }
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
      #if os(iOS)
      .fullScreenCover(isPresented: Binding(
        get: { appController.nagScreenReminderID != nil },
        set: { if !$0 { appController.dismissNagScreen() } }
      )) {
        nagScreenContent
      }
      #else
      .sheet(isPresented: Binding(
        get: { appController.nagScreenReminderID != nil },
        set: { if !$0 { appController.dismissNagScreen() } }
      )) {
        nagScreenContent
      }
      #endif
      .safeAreaInset(edge: .bottom) {
        if debugNotificationsEnabled {
          debugPanel
        }
      }
    }
  }

  @ViewBuilder
  private var nagScreenContent: some View {
    if let reminderID = appController.nagScreenReminderID,
       let reminder = viewModel.reminders.first(where: { $0.id == reminderID }) {
      NagScreenView(
        title: reminder.title,
        snoozePresets: viewModel.nagPolicy.snoozePresetMinutes,
        onSnooze: { minutes in
          Task {
            await appController.snooze(reminderID: reminderID, minutes: minutes)
            await viewModel.refresh()
          }
          appController.dismissNagScreen()
        },
        onMarkDone: {
          Task {
            await appController.markDone(reminderID: reminderID)
            await viewModel.refresh()
          }
          appController.dismissNagScreen()
        },
        onStop: {
          Task {
            await appController.stopNagging(reminderID: reminderID)
            await viewModel.refresh()
          }
          appController.dismissNagScreen()
        }
      )
    } else {
      NagScreenView(
        title: "Reminder",
        onSnooze: { _ in appController.dismissNagScreen() },
        onStop: { appController.dismissNagScreen() }
      )
    }
  }

  private var debugPanel: some View {
    HStack(spacing: 12) {
      Button("Simulate Nag") {
        if let first = viewModel.visibleReminders.first {
          appController.handle(url: DeepLinkFactory.nagScreenURL(reminderID: first.id))
        }
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
